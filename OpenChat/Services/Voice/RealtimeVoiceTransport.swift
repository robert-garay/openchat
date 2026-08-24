import Foundation

enum RealtimeVoiceError: LocalizedError {
    case notConnected
    case invalidURL
    case audioEngineUnavailable

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "The voice session isn't connected."
        case .invalidURL:
            return "Couldn't build the realtime voice endpoint URL."
        case .audioEngineUnavailable:
            return "Couldn't start the microphone."
        }
    }
}

/// Abstracts the WebSocket transport so `RealtimeVoiceSession` can be unit
/// tested without opening a real network connection. Mirrors the
/// `PathMonitoring` abstraction used by `NetworkMonitor`.
protocol RealtimeVoiceTransport: Sendable {
    func connect(url: URL, apiKey: String) async throws
    func send(_ data: Data) async throws
    /// Raw frames from the server, one element per WebSocket message.
    /// Finishes (with or without an error) when the connection closes.
    func receive() -> AsyncThrowingStream<Data, Error>
    func close() async
}

/// `URLSessionWebSocketTask`-backed transport talking to the OpenAI Realtime API.
///
/// `connect()` doesn't return until the handshake has genuinely completed —
/// `task.resume()` only *starts* it asynchronously. Without waiting, the
/// caller's first `send()` (the initial `session.update`, sent immediately
/// after `connect()` returns) races the handshake and fails with "Socket is
/// not connected" whenever real network latency beats the race, which
/// local/simulator testing rarely surfaces since latency there is near zero.
/// `URLSessionWebSocketDelegate` is the reliable way to observe handshake
/// completion — `didOpenWithProtocol` fires on success, `didCompleteWithError`
/// on failure (auth rejected, non-101 response, network failure, etc.).
final class URLSessionRealtimeTransport: NSObject, RealtimeVoiceTransport, URLSessionWebSocketDelegate, @unchecked Sendable {
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private var task: URLSessionWebSocketTask?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()

    func connect(url: URL, apiKey: String) async throws {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        let task = session.webSocketTask(with: request)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock {
                self.task = task
                self.connectContinuation = continuation
            }
            task.resume()
        }
    }

    func send(_ data: Data) async throws {
        guard let task = lock.withLock({ self.task }) else { throw RealtimeVoiceError.notConnected }
        try await task.send(.data(data))
    }

    func receive() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let loopTask = Task { [weak self] in
                while true {
                    guard let self, let task = self.lock.withLock({ self.task }) else {
                        continuation.finish(throwing: RealtimeVoiceError.notConnected)
                        return
                    }
                    do {
                        let message = try await task.receive()
                        switch message {
                        case .data(let data):
                            continuation.yield(data)
                        case .string(let text):
                            continuation.yield(Data(text.utf8))
                        @unknown default:
                            break
                        }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }
            continuation.onTermination = { _ in loopTask.cancel() }
        }
    }

    func close() async {
        let task = lock.withLock { () -> URLSessionWebSocketTask? in
            defer { self.task = nil }
            return self.task
        }
        task?.cancel(with: .normalClosure, reason: nil)
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        resumeConnectContinuation(throwing: nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        resumeConnectContinuation(throwing: error ?? RealtimeVoiceError.notConnected)
    }

    /// Only actually resumes on the *first* callback after `connect()` starts —
    /// `didCompleteWithError` also fires on a normal `close()` of an already-open
    /// connection, by which point the continuation has already been consumed.
    private func resumeConnectContinuation(throwing error: Error?) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { connectContinuation = nil }
            return connectContinuation
        }
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

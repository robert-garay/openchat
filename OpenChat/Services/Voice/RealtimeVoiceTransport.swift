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
final class URLSessionRealtimeTransport: RealtimeVoiceTransport, @unchecked Sendable {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private let lock = NSLock()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(url: URL, apiKey: String) async throws {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        let task = session.webSocketTask(with: request)
        task.resume()
        lock.withLock { self.task = task }

        // `resume()` only starts the handshake asynchronously — it does not wait
        // for the socket to actually be open. Without this, the caller's first
        // `send()` (session.update, sent immediately after `connect()` returns)
        // races the handshake and fails with "Socket is not connected" whenever
        // real network latency beats the race, which local/simulator testing
        // rarely surfaces. A ping's completion handler only fires once the
        // WebSocket connection is genuinely established (or failed), so it's the
        // standard way to await that with `URLSessionWebSocketTask`.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
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
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

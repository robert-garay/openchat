import Foundation

/// Turns a streaming HTTP response into an `AsyncThrowingStream` of raw SSE
/// `data:` payloads (everything after the `data: ` prefix on each event).
/// Provider-specific clients decode those payloads into their own schemas.
enum ServerSentEventStream {
    static func dataPayloads(for request: URLRequest, session: URLSession) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)

                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        continuation.finish(throwing: ChatServiceError.http(status: http.statusCode, body: errorBody))
                        return
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let payload = Self.payload(fromSSELine: line) else { continue }
                        if payload == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        continuation.yield(payload)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ChatServiceError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func payload(fromSSELine line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let value = line.dropFirst("data:".count)
        return value.trimmingCharacters(in: .whitespaces)
    }
}

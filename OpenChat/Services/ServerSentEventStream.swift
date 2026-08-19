import Foundation

/// Turns a streaming HTTP response into an `AsyncThrowingStream` of raw SSE
/// `data:` payloads (everything after the `data: ` prefix on each event).
/// Provider-specific clients decode those payloads into their own schemas.
///
/// Cost safety: retries are only attempted before the first payload has been
/// yielded to the consumer — nothing has streamed yet, so nothing has been
/// billed. Once a payload has been yielded, a subsequent transient failure
/// is surfaced as `ChatServiceError.connectionDropped` rather than retried,
/// so callers can decide how to resume (see `BackgroundGenerationService`).
enum ServerSentEventStream {
    static func dataPayloads(
        for request: URLRequest,
        session: URLSession,
        retryPolicy: RetryPolicy = .costSensitive,
        networkMonitor: NetworkMonitor = .shared
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var hasYieldedAny = false
                var attempt = 1

                while true {
                    do {
                        let (bytes, response) = try await session.bytes(for: request)

                        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                            var errorBody = ""
                            for try await line in bytes.lines {
                                errorBody += line
                            }
                            throw ChatServiceError.http(status: http.statusCode, body: errorBody)
                        }

                        for try await line in bytes.lines {
                            try Task.checkCancellation()
                            guard let payload = Self.payload(fromSSELine: line) else { continue }
                            if payload == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            hasYieldedAny = true
                            continuation.yield(payload)
                        }
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        continuation.finish(throwing: ChatServiceError.cancelled)
                        return
                    } catch {
                        if hasYieldedAny {
                            continuation.finish(throwing: Self.midStreamError(for: error))
                            return
                        }
                        guard attempt < retryPolicy.maxAttempts,
                              RetryPolicy.isRetryable(error, costSensitive: retryPolicy.costSensitive) else {
                            continuation.finish(throwing: Self.preStreamError(for: error))
                            return
                        }
                        let connected = await networkMonitor.isConnected
                        if connected {
                            try? await Task.sleep(for: retryPolicy.delay(forAttempt: attempt))
                        } else {
                            await networkMonitor.waitForConnection()
                        }
                        attempt += 1
                    }
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

    private static func midStreamError(for error: Error) -> Error {
        if RetryPolicy.isRetryable(error, costSensitive: true) {
            return ChatServiceError.connectionDropped
        }
        return error
    }

    private static func preStreamError(for error: Error) -> Error {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return ChatServiceError.timedOut
        }
        return error
    }
}

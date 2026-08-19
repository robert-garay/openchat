import Foundation

/// Retries a network operation according to `RetryPolicy`, waiting for
/// connectivity to return when the device is offline instead of burning
/// through attempts immediately.
///
/// IMPORTANT — cost safety: only wrap operations that are atomic from a
/// billing standpoint (the whole response arrives, or nothing does). Never
/// wrap an operation after it has started producing content the provider
/// may already have generated and billed for — see `ServerSentEventStream`
/// for how the streaming path draws that line.
enum NetworkRetrier {
    static func perform<T: Sendable>(
        policy: RetryPolicy = .default,
        networkMonitor: NetworkMonitor = .shared,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch {
                try Task.checkCancellation()
                guard attempt < policy.maxAttempts,
                      RetryPolicy.isRetryable(error, costSensitive: policy.costSensitive) else {
                    throw error
                }
                let connected = await networkMonitor.isConnected
                if connected {
                    try? await Task.sleep(for: policy.delay(forAttempt: attempt))
                } else {
                    await networkMonitor.waitForConnection()
                }
                attempt += 1
            }
        }
    }
}

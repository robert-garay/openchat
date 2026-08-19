import Testing
import Foundation
@testable import OpenChat

struct NetworkRetrierTests {
    @Test("returns the result on first success without retrying")
    func succeedsImmediately() async throws {
        let attempts = Counter()
        let result = try await NetworkRetrier.perform(
            policy: RetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5),
            networkMonitor: NetworkMonitor(pathMonitor: AlwaysConnected())
        ) {
            await attempts.increment()
            return "ok"
        }
        #expect(result == "ok")
        #expect(await attempts.count == 1)
    }

    @Test("retries a retryable error up to maxAttempts then succeeds")
    func retriesThenSucceeds() async throws {
        let attempts = Counter()
        let result = try await NetworkRetrier.perform(
            policy: RetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5),
            networkMonitor: NetworkMonitor(pathMonitor: AlwaysConnected())
        ) {
            let count = await attempts.increment()
            if count < 3 {
                throw URLError(.notConnectedToInternet)
            }
            return "ok"
        }
        #expect(result == "ok")
        #expect(await attempts.count == 3)
    }

    @Test("throws immediately for a non-retryable error")
    func doesNotRetryNonRetryableError() async {
        let attempts = Counter()
        struct SomeError: Error {}
        await #expect(throws: SomeError.self) {
            try await NetworkRetrier.perform(
                policy: RetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5),
                networkMonitor: NetworkMonitor(pathMonitor: AlwaysConnected())
            ) {
                _ = await attempts.increment()
                throw SomeError()
            }
        }
        #expect(await attempts.count == 1)
    }

    @Test("throws the last error after exhausting maxAttempts")
    func throwsAfterExhaustingAttempts() async {
        let attempts = Counter()
        await #expect(throws: URLError.self) {
            try await NetworkRetrier.perform(
                policy: RetryPolicy(maxAttempts: 2, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5),
                networkMonitor: NetworkMonitor(pathMonitor: AlwaysConnected())
            ) {
                _ = await attempts.increment()
                throw URLError(.notConnectedToInternet)
            }
        }
        #expect(await attempts.count == 2)
    }
}

private actor Counter {
    private(set) var count = 0
    @discardableResult
    func increment() -> Int {
        count += 1
        return count
    }
}

private struct AlwaysConnected: PathMonitoring {
    func start(onUpdate: @escaping @Sendable (Bool) async -> Void) async {}
}

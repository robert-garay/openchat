import Testing
import Foundation
@testable import OpenChat

struct RetryPolicyTests {
    @Test("default policy retries connection-lost and timeout errors")
    func defaultPolicyRetriesTransientURLErrors() {
        #expect(RetryPolicy.isRetryable(URLError(.networkConnectionLost), costSensitive: false))
        #expect(RetryPolicy.isRetryable(URLError(.timedOut), costSensitive: false))
        #expect(RetryPolicy.isRetryable(URLError(.notConnectedToInternet), costSensitive: false))
    }

    @Test("cost-sensitive policy excludes timeout and connection-lost")
    func costSensitivePolicyExcludesAmbiguousErrors() {
        #expect(!RetryPolicy.isRetryable(URLError(.timedOut), costSensitive: true))
        #expect(!RetryPolicy.isRetryable(URLError(.networkConnectionLost), costSensitive: true))
    }

    @Test("cost-sensitive policy still retries pre-connection failures")
    func costSensitivePolicyRetriesPreConnectionFailures() {
        #expect(RetryPolicy.isRetryable(URLError(.notConnectedToInternet), costSensitive: true))
        #expect(RetryPolicy.isRetryable(URLError(.cannotFindHost), costSensitive: true))
        #expect(RetryPolicy.isRetryable(URLError(.dnsLookupFailed), costSensitive: true))
    }

    @Test("429 and 5xx are always retryable, other HTTP statuses are not")
    func httpStatusClassification() {
        #expect(RetryPolicy.isRetryable(ChatServiceError.http(status: 429, body: ""), costSensitive: true))
        #expect(RetryPolicy.isRetryable(ChatServiceError.http(status: 503, body: ""), costSensitive: true))
        #expect(!RetryPolicy.isRetryable(ChatServiceError.http(status: 400, body: ""), costSensitive: true))
        #expect(!RetryPolicy.isRetryable(ChatServiceError.http(status: 401, body: ""), costSensitive: false))
    }

    @Test("non-URLError, non-ChatServiceError errors are never retryable")
    func unknownErrorsAreNotRetryable() {
        struct SomeError: Error {}
        #expect(!RetryPolicy.isRetryable(SomeError(), costSensitive: false))
    }

    @Test("delay grows exponentially and is capped")
    func delayGrowsAndCaps() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelayMilliseconds: 100, maxDelayMilliseconds: 1_000)
        let first = policy.delay(forAttempt: 1)
        let second = policy.delay(forAttempt: 2)
        let capped = policy.delay(forAttempt: 10)
        #expect(first < second)
        #expect(capped <= .milliseconds(1_200)) // cap + max jitter headroom
    }
}

import Foundation

/// Classifies whether a network failure is safe to retry, and computes
/// exponential backoff with jitter for the next attempt.
///
/// Two flavors exist because retrying is only ever cost-neutral for requests
/// that are atomic from a billing standpoint. `costSensitive` policies are
/// used for anything that reaches a paid chat-completion endpoint; they
/// exclude ambiguous failures (`.timedOut`, `.networkConnectionLost`) that
/// could mean the request already reached the provider and started (and
/// will be billed for) generating a response. `default` is used for
/// idempotent, cost-free calls (search, model catalogs, balance checks).
struct RetryPolicy: Sendable {
    var maxAttempts: Int = 3
    var baseDelayMilliseconds: Double = 500
    var maxDelayMilliseconds: Double = 8_000
    var costSensitive: Bool = false

    static let `default` = RetryPolicy()
    static let costSensitive = RetryPolicy(costSensitive: true)

    /// Pre-connection failures: the request could not possibly have reached
    /// the provider, so retrying can never duplicate billed work.
    private static let preConnectionCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
        .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
    ]

    /// Ambiguous failures: the request may already have reached the
    /// provider. Safe to retry for cost-free calls only.
    private static let ambiguousCodes: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost,
    ]

    static func isRetryable(_ error: Error, costSensitive: Bool) -> Bool {
        if case ChatServiceError.http(let status, _) = error {
            return status == 429 || (500...599).contains(status)
        }
        guard let urlError = error as? URLError else { return false }
        if preConnectionCodes.contains(urlError.code) { return true }
        if costSensitive { return false }
        return ambiguousCodes.contains(urlError.code)
    }

    func delay(forAttempt attempt: Int) -> Duration {
        let exponent = Double(max(attempt - 1, 0))
        let raw = baseDelayMilliseconds * pow(2, exponent)
        let capped = min(raw, maxDelayMilliseconds)
        let jitter = Double.random(in: 0.8...1.2)
        return .milliseconds(Int(capped * jitter))
    }
}

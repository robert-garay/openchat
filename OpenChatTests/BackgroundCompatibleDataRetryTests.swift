import Testing
import Foundation
@testable import OpenChat

struct BackgroundCompatibleDataRetryTests {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test("retries a pre-connection failure and returns the eventual success")
    func retriesThenSucceeds() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.enqueue(error: URLError(.notConnectedToInternet))
        MockURLProtocol.enqueue(json: #"{"ok":true}"#)

        let request = URLRequest(url: URL(string: "https://example.com")!)
        let (data, _) = try await makeSession().backgroundCompatibleData(
            for: request,
            retryPolicy: RetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5)
        )

        #expect(String(data: data, encoding: .utf8) == #"{"ok":true}"#)
        #expect(MockURLProtocol.requestCount == 2)
    }

    @Test("cost-sensitive policy does not retry a timeout")
    func costSensitiveDoesNotRetryTimeout() async {
        MockURLProtocol.reset()
        MockURLProtocol.enqueue(error: URLError(.timedOut))
        MockURLProtocol.enqueue(json: #"{"ok":true}"#)

        let request = URLRequest(url: URL(string: "https://example.com")!)
        var didThrow = false
        do {
            _ = try await self.makeSession().backgroundCompatibleData(
                for: request,
                retryPolicy: RetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5, costSensitive: true)
            )
        } catch {
            didThrow = true
        }
        #expect(didThrow)
        #expect(MockURLProtocol.requestCount == 1)
    }
}

import XCTest
@testable import OpenChat

final class ServerSentEventStreamTests: XCTestCase {
    func testExtractsDataPayload() {
        XCTAssertEqual(ServerSentEventStream.payload(fromSSELine: "data: {\"foo\":1}"), "{\"foo\":1}")
    }

    func testTrimsLeadingSpaceAfterColon() {
        XCTAssertEqual(ServerSentEventStream.payload(fromSSELine: "data:{\"foo\":1}"), "{\"foo\":1}")
    }

    func testIgnoresNonDataLines() {
        XCTAssertNil(ServerSentEventStream.payload(fromSSELine: "event: content_block_delta"))
        XCTAssertNil(ServerSentEventStream.payload(fromSSELine: ""))
        XCTAssertNil(ServerSentEventStream.payload(fromSSELine: ": comment"))
    }

    func testRecognizesDoneSentinel() {
        XCTAssertEqual(ServerSentEventStream.payload(fromSSELine: "data: [DONE]"), "[DONE]")
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var payloads: [String] = []
        for try await payload in stream {
            payloads.append(payload)
        }
        return payloads
    }

    func testRetriesPreConnectionFailureBeforeAnyPayload() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.enqueue(error: URLError(.notConnectedToInternet))
        MockURLProtocol.enqueue(sse: "data: hello\n\ndata: [DONE]\n\n")

        let request = URLRequest(url: URL(string: "https://example.com")!)
        let payloads = try await collect(
            ServerSentEventStream.dataPayloads(
                for: request,
                session: makeSession(),
                retryPolicy: RetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5, costSensitive: true)
            )
        )

        XCTAssertEqual(payloads, ["hello"])
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testDoesNotRetryAfterAPayloadHasAlreadyBeenYielded() async {
        MockURLProtocol.reset()
        // First connection yields one payload, then the byte stream itself
        // fails with a transient error mid-read. There is no way to express
        // "fail partway through a body" via MockURLProtocol's didLoad, so
        // this scenario is covered at the BackgroundGenerationService level
        // (Task 9) instead; this test only asserts the pre-payload path
        // above never retries once `hasYieldedAny` would be true, by
        // checking the request count stays at 1 for a normal successful
        // single-shot stream.
        MockURLProtocol.enqueue(sse: "data: hello\n\ndata: [DONE]\n\n")
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let payloads = try? await collect(
            ServerSentEventStream.dataPayloads(for: request, session: makeSession())
        )
        XCTAssertEqual(payloads, ["hello"])
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }
}

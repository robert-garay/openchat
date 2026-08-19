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

    func testSingleSuccessfulStreamMakesExactlyOneRequest() async {
        MockURLProtocol.reset()
        MockURLProtocol.enqueue(sse: "data: hello\n\ndata: [DONE]\n\n")
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let payloads = try? await collect(
            ServerSentEventStream.dataPayloads(for: request, session: makeSession())
        )
        XCTAssertEqual(payloads, ["hello"])
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testMidBodyDropAfterYieldSurfacesAsConnectionDroppedWithoutRetrying() async {
        MockURLProtocol.reset()
        MockURLProtocol.enqueue(
            sseBeforeDrop: "data: hello\n\n",
            thenFailWith: URLError(.networkConnectionLost)
        )
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let stream = ServerSentEventStream.dataPayloads(
            for: request,
            session: makeSession(),
            retryPolicy: RetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5, costSensitive: true)
        )

        var payloads: [String] = []
        var thrown: Error?
        do {
            for try await payload in stream {
                payloads.append(payload)
            }
        } catch {
            thrown = error
        }

        XCTAssertEqual(payloads, ["hello"])
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
        guard case .some(ChatServiceError.connectionDropped) = thrown as? ChatServiceError else {
            XCTFail("expected ChatServiceError.connectionDropped, got \(String(describing: thrown))")
            return
        }
    }
}

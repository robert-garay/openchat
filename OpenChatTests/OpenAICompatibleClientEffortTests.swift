import XCTest
@testable import OpenChat

final class OpenAICompatibleClientEffortTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testReasoningEffortIncludedInRequestBody() async throws {
        MockURLProtocol.enqueue(sse: """
        data: {"choices":[{"delta":{"content":"Hi"}}]}

        data: [DONE]

        """)

        let client = OpenAICompatibleClient(session: makeSession())
        var text = ""
        for try await event in client.streamReply(
            turns: [ChatTurn(role: .user, content: "hello")],
            model: "o3-mini",
            baseURL: "https://example.com/v1",
            apiKey: "k",
            supportsImageGen: false,
            effort: .high
        ) {
            if case .text(let delta) = event { text += delta }
        }

        XCTAssertEqual(text, "Hi")
        let body = MockURLProtocol.lastRequestBody
        XCTAssertNotNil(body, "Request body was not captured")
        let json = try JSONSerialization.jsonObject(with: body!) as? [String: Any]
        XCTAssertEqual(json?["reasoning_effort"] as? String, "high")
    }

    func testReasoningEffortOmittedWhenNotSet() async throws {
        MockURLProtocol.enqueue(sse: """
        data: {"choices":[{"delta":{"content":"Hi"}}]}

        data: [DONE]

        """)

        let client = OpenAICompatibleClient(session: makeSession())
        var text = ""
        for try await event in client.streamReply(
            turns: [ChatTurn(role: .user, content: "hello")],
            model: "gpt-4o",
            baseURL: "https://example.com/v1",
            apiKey: "k",
            supportsImageGen: false,
            effort: nil
        ) {
            if case .text(let delta) = event { text += delta }
        }

        XCTAssertEqual(text, "Hi")
        let body = MockURLProtocol.lastRequestBody
        XCTAssertNotNil(body, "Request body was not captured")
        let json = try JSONSerialization.jsonObject(with: body!) as? [String: Any]
        XCTAssertNil(json?["reasoning_effort"])
    }
}

import XCTest
@testable import OpenChat

final class AnthropicClientReasoningTests: XCTestCase {
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

    func testThinkingEnabledWhenReasoningEnabled() async throws {
        MockURLProtocol.enqueue(sse: """
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}

        data: {"type":"message_stop"}

        """)

        let client = AnthropicClient(session: makeSession())
        var text = ""
        for try await event in client.streamReply(
            turns: [ChatTurn(role: .user, content: "hello")],
            model: "claude-sonnet-4",
            baseURL: "https://example.com/v1",
            apiKey: "k",
            supportsImageGen: false,
            effort: nil,
            reasoningEnabled: true
        ) {
            if case .text(let delta) = event { text += delta }
        }

        XCTAssertEqual(text, "Hi")
        let body = MockURLProtocol.lastRequestBody
        XCTAssertNotNil(body, "Request body was not captured")
        let json = try JSONSerialization.jsonObject(with: body!) as? [String: Any]
        let thinking = json?["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["type"] as? String, "enabled")
        XCTAssertEqual(thinking?["budget_tokens"] as? Int, 16000)
    }

    func testThinkingOmittedWhenReasoningDisabled() async throws {
        MockURLProtocol.enqueue(sse: """
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}

        data: {"type":"message_stop"}

        """)

        let client = AnthropicClient(session: makeSession())
        var text = ""
        for try await event in client.streamReply(
            turns: [ChatTurn(role: .user, content: "hello")],
            model: "claude-sonnet-4",
            baseURL: "https://example.com/v1",
            apiKey: "k",
            supportsImageGen: false,
            effort: nil,
            reasoningEnabled: false
        ) {
            if case .text(let delta) = event { text += delta }
        }

        XCTAssertEqual(text, "Hi")
        let body = MockURLProtocol.lastRequestBody
        XCTAssertNotNil(body, "Request body was not captured")
        let json = try JSONSerialization.jsonObject(with: body!) as? [String: Any]
        XCTAssertNil(json?["thinking"])
    }

    func testThinkingOmittedWhenReasoningNotSet() async throws {
        MockURLProtocol.enqueue(sse: """
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}

        data: {"type":"message_stop"}

        """)

        let client = AnthropicClient(session: makeSession())
        var text = ""
        for try await event in client.streamReply(
            turns: [ChatTurn(role: .user, content: "hello")],
            model: "claude-sonnet-4",
            baseURL: "https://example.com/v1",
            apiKey: "k"
        ) {
            if case .text(let delta) = event { text += delta }
        }

        XCTAssertEqual(text, "Hi")
        let body = MockURLProtocol.lastRequestBody
        XCTAssertNotNil(body, "Request body was not captured")
        let json = try JSONSerialization.jsonObject(with: body!) as? [String: Any]
        XCTAssertNil(json?["thinking"])
    }
}

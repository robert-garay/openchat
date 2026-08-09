import XCTest
@testable import OpenChat

/// Regression coverage for the first-round streaming path used when tools are
/// registered. The clients must stop after the streamed round when the model
/// returns plain text, and only fall through to the non-streaming tool loop
/// when actual tool calls arrive.
final class StreamingToolLoopTests: XCTestCase {

    // MARK: - Fixtures

    private let tools = [
        ChatToolDefinition(
            name: "web_search",
            description: "Search the web",
            parametersJSON: #"{"type":"object","properties":{"query":{"type":"string"}}}"#
        )
    ]

    private let turns = [ChatTurn(role: .user, content: "hi")]

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

    private func collect(
        _ stream: AsyncThrowingStream<ChatStreamEvent, Error>
    ) async throws -> String {
        var text = ""
        for try await event in stream {
            if case .text(let delta) = event { text += delta }
        }
        return text
    }

    // MARK: - OpenAI-compatible

    func testOpenAIStopsAfterStreamedRoundWhenNoToolCalls() async throws {
        MockURLProtocol.enqueue(sse: """
        data: {"choices":[{"delta":{"content":"Hel"}}]}

        data: {"choices":[{"delta":{"content":"lo"}}]}

        data: [DONE]

        """)
        // If the client wrongly continues the tool loop it will issue a second,
        // non-streaming request and append this duplicate answer.
        MockURLProtocol.enqueue(json: #"{"choices":[{"message":{"content":"DUPLICATE"}}]}"#)

        let client = OpenAICompatibleClient(session: makeSession())
        let text = try await collect(
            client.streamReply(
                turns: turns,
                model: "gpt-4o",
                baseURL: "https://example.com/v1",
                apiKey: "k",
                tools: tools,
                executeTool: { _ in "unused" },
                supportsImageGen: false,
                effort: nil,
                reasoningEnabled: nil
            )
        )

        XCTAssertEqual(text, "Hello")
        XCTAssertEqual(MockURLProtocol.requestCount, 1, "streamed round should be the only request")
    }

    func testOpenAIRunsToolLoopWhenStreamEmitsToolCalls() async throws {
        MockURLProtocol.enqueue(sse: """
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"web_search","arguments":"{\\"query\\":"}}]}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"swift\\"}"}}]}}]}

        data: [DONE]

        """)
        MockURLProtocol.enqueue(json: #"{"choices":[{"message":{"content":"Final answer"}}]}"#)

        let executed = ToolCallRecorder()
        let client = OpenAICompatibleClient(session: makeSession())
        let text = try await collect(
            client.streamReply(
                turns: turns,
                model: "gpt-4o",
                baseURL: "https://example.com/v1",
                apiKey: "k",
                tools: tools,
                executeTool: { call in
                    await executed.record(call)
                    return "results"
                },
                supportsImageGen: false,
                effort: nil,
                reasoningEnabled: nil
            )
        )

        XCTAssertEqual(text, "Final answer")
        let calls = await executed.calls
        XCTAssertEqual(calls.map(\.name), ["web_search"])
        XCTAssertEqual(calls.first?.argumentsJSON, #"{"query":"swift"}"#)
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    // MARK: - Anthropic

    func testAnthropicStopsAfterStreamedRoundWhenNoToolCalls() async throws {
        MockURLProtocol.enqueue(sse: """
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text"}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}}

        data: {"type":"message_stop"}

        """)
        MockURLProtocol.enqueue(json: #"{"content":[{"type":"text","text":"DUPLICATE"}]}"#)

        let client = AnthropicClient(session: makeSession())
        let text = try await collect(
            client.streamReply(
                turns: turns,
                model: "claude-opus-4-6",
                baseURL: "https://example.com/v1",
                apiKey: "k",
                tools: tools,
                executeTool: { _ in "unused" },
                supportsImageGen: false,
                effort: nil,
                reasoningEnabled: nil
            )
        )

        XCTAssertEqual(text, "Hello")
        XCTAssertEqual(MockURLProtocol.requestCount, 1, "streamed round should be the only request")
    }

    func testAnthropicRunsToolLoopWhenStreamEmitsToolUse() async throws {
        MockURLProtocol.enqueue(sse: """
        data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"web_search"}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"query\\":"}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\\"swift\\"}"}}

        data: {"type":"message_stop"}

        """)
        MockURLProtocol.enqueue(json: #"{"content":[{"type":"text","text":"Final answer"}]}"#)

        let executed = ToolCallRecorder()
        let client = AnthropicClient(session: makeSession())
        let text = try await collect(
            client.streamReply(
                turns: turns,
                model: "claude-opus-4-6",
                baseURL: "https://example.com/v1",
                apiKey: "k",
                tools: tools,
                executeTool: { call in
                    await executed.record(call)
                    return "results"
                },
                supportsImageGen: false,
                effort: nil,
                reasoningEnabled: nil
            )
        )

        XCTAssertEqual(text, "Final answer")
        let calls = await executed.calls
        XCTAssertEqual(calls.map(\.name), ["web_search"])
        XCTAssertEqual(calls.first?.argumentsJSON, #"{"query":"swift"}"#)
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    /// A streamed tool call whose fragments never carry an id/name must not be
    /// mistaken for "no tool calls" — the loop still needs to continue.
    func testOpenAIMalformedToolCallFragmentsDoNotStreamAsAnswer() async throws {
        MockURLProtocol.enqueue(sse: """
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{}"}}]}}]}

        data: [DONE]

        """)
        MockURLProtocol.enqueue(json: #"{"choices":[{"message":{"content":"Recovered"}}]}"#)

        let client = OpenAICompatibleClient(session: makeSession())
        let text = try await collect(
            client.streamReply(
                turns: turns,
                model: "gpt-4o",
                baseURL: "https://example.com/v1",
                apiKey: "k",
                tools: tools,
                executeTool: { _ in "results" },
                supportsImageGen: false,
                effort: nil,
                reasoningEnabled: nil
            )
        )

        XCTAssertEqual(text, "Recovered")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }
}

// MARK: - Helpers

private actor ToolCallRecorder {
    private(set) var calls: [ChatToolCall] = []
    func record(_ call: ChatToolCall) { calls.append(call) }
}

/// Serves queued canned responses and counts how many requests were issued.
final class MockURLProtocol: URLProtocol {
    private struct Stub {
        let body: Data
        let contentType: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [Stub] = []
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var capturedRequestBody: Data?

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        stubs = []
        count = 0
        capturedRequestBody = nil
    }

    static var lastRequestBody: Data? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequestBody
    }

    static func enqueue(sse: String) {
        lock.lock()
        defer { lock.unlock() }
        stubs.append(Stub(body: Data(sse.utf8), contentType: "text/event-stream"))
    }

    static func enqueue(json: String) {
        lock.lock()
        defer { lock.unlock() }
        stubs.append(Stub(body: Data(json.utf8), contentType: "application/json"))
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    private static func next() -> Stub? {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return stubs.isEmpty ? nil : stubs.removeFirst()
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequestBody = request.httpBody ?? request.httpBodyStream.flatMap {
            $0.readToEnd(maxLength: 10_000_000)
        }
        Self.lock.unlock()
        guard let stub = Self.next() else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": stub.contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension InputStream {
    func readToEnd(maxLength: Int) -> Data? {
        open()
        defer { close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while hasBytesAvailable {
            let read = self.read(&buffer, maxLength: bufferSize)
            if read < 0 {
                return nil
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
            if data.count > maxLength {
                return nil
            }
        }
        return data.isEmpty ? nil : data
    }
}

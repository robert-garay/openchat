import Foundation

/// Speaks Anthropic's native `/messages` streaming format for Claude models.
struct AnthropicClient: ChatCompletionClient {
    var session: URLSession = .shared

    func streamReply(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        tools: [ChatToolDefinition],
        executeTool: @escaping @Sendable (ChatToolCall) async throws -> String,
        supportsImageGen: Bool,
        effort: EffortLevel?,
        reasoningEnabled: Bool?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        // Anthropic Messages API does not return generated bitmaps; ignore supportsImageGen.
        // Anthropic has no equivalent of the OpenAI `reasoning_effort` parameter.
        _ = supportsImageGen
        _ = effort
        _ = reasoningEnabled
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if tools.isEmpty {
                        try await Self.streamText(
                            turns: turns,
                            model: model,
                            baseURL: baseURL,
                            apiKey: apiKey,
                            reasoningEnabled: reasoningEnabled,
                            session: session,
                            continuation: continuation
                        )
                    } else {
                        try await Self.runToolLoop(
                            turns: turns,
                            model: model,
                            baseURL: baseURL,
                            apiKey: apiKey,
                            tools: tools,
                            executeTool: executeTool,
                            reasoningEnabled: reasoningEnabled,
                            session: session,
                            continuation: continuation
                        )
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ChatServiceError.cancelled)
                } catch let urlError as URLError where urlError.code == .timedOut {
                    continuation.finish(throwing: ChatServiceError.timedOut)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Tool loop

    private static func runToolLoop(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        tools: [ChatToolDefinition],
        executeTool: @escaping @Sendable (ChatToolCall) async throws -> String,
        reasoningEnabled: Bool?,
        session: URLSession,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async throws {
        var workingTurns = turns

        // First round: stream with tools so the user sees text immediately when the model
        // does not invoke any tools. If it does invoke tools, fall back to the non-streaming
        // loop for the remaining rounds.
        try Task.checkCancellation()
        if let toolCalls = try await streamText(
            turns: workingTurns,
            model: model,
            baseURL: baseURL,
            apiKey: apiKey,
            tools: tools,
            reasoningEnabled: reasoningEnabled,
            session: session,
            continuation: continuation
        ) {
            // When fragments arrived but none resolved into a usable call
            // (missing id/name), leave the turns untouched and let the
            // non-streaming round below retry: appending an empty assistant
            // turn with no tool calls is rejected by some providers.
            if !toolCalls.isEmpty {
                workingTurns.append(
                    ChatTurn(role: .assistant, content: "", toolCalls: toolCalls)
                )
                for call in toolCalls {
                    let output = try await executeTool(call)
                    workingTurns.append(
                        ChatTurn(role: .tool, content: output, toolCallID: call.id)
                    )
                }
            }
        } else {
            return
        }

        for _ in 1..<WebSearchService.maxToolRounds {
            try Task.checkCancellation()
            let result = try await complete(
                turns: workingTurns,
                model: model,
                baseURL: baseURL,
                apiKey: apiKey,
                tools: tools,
                reasoningEnabled: reasoningEnabled,
                session: session
            )

            if result.hasToolCalls {
                workingTurns.append(
                    ChatTurn(role: .assistant, content: result.text, toolCalls: result.toolCalls)
                )
                for call in result.toolCalls {
                    let output = try await executeTool(call)
                    workingTurns.append(
                        ChatTurn(role: .tool, content: output, toolCallID: call.id)
                    )
                }
                continue
            }

            if !result.text.isEmpty {
                continuation.yield(.text(result.text))
            }
            return
        }

        try await streamText(
            turns: workingTurns,
            model: model,
            baseURL: baseURL,
            apiKey: apiKey,
            reasoningEnabled: reasoningEnabled,
            session: session,
            continuation: continuation
        )
    }

    // MARK: - Non-streaming completion

    private static func complete(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        tools: [ChatToolDefinition],
        reasoningEnabled: Bool?,
        session: URLSession
    ) async throws -> ChatCompletionResult {
        var request = try makeRequest(baseURL: baseURL, apiKey: apiKey)
        let body = try encodeBody(turns: turns, model: model, stream: false, tools: tools, reasoningEnabled: reasoningEnabled)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ChatServiceError.http(status: http.statusCode, body: bodyText)
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        var textParts: [String] = []
        var toolCalls: [ChatToolCall] = []

        for block in decoded.content ?? [] {
            switch block.type {
            case "text":
                if let text = block.text, !text.isEmpty {
                    textParts.append(text)
                }
            case "tool_use":
                if let id = block.id, let name = block.name {
                    let argsJSON: String
                    if let input = block.input {
                        argsJSON = (try? String(data: JSONEncoder().encode(input), encoding: .utf8)) ?? "{}"
                    } else {
                        argsJSON = "{}"
                    }
                    toolCalls.append(ChatToolCall(id: id, name: name, argumentsJSON: argsJSON))
                }
            default:
                continue
            }
        }

        return ChatCompletionResult(text: textParts.joined(), toolCalls: toolCalls)
    }

    // MARK: - Streaming text

    private static func streamText(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        reasoningEnabled: Bool?,
        session: URLSession,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async throws {
        _ = try await streamText(
            turns: turns,
            model: model,
            baseURL: baseURL,
            apiKey: apiKey,
            tools: [],
            reasoningEnabled: reasoningEnabled,
            session: session,
            continuation: continuation
        )
    }

    /// Streams a request that may include tools. Returns any tool calls the model emits;
    /// if it returns `nil`, the streamed text has already been yielded.
    private static func streamText(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        tools: [ChatToolDefinition],
        reasoningEnabled: Bool?,
        session: URLSession,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async throws -> [ChatToolCall]? {
        var request = try makeRequest(baseURL: baseURL, apiKey: apiKey)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try encodeBody(turns: turns, model: model, stream: true, tools: tools, reasoningEnabled: reasoningEnabled)

        var accumulator = ToolCallAccumulator()

        let upstream = ServerSentEventStream.dataPayloads(for: request, session: session)
        for try await payload in upstream {
            guard let data = payload.data(using: .utf8) else { continue }
            guard let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else { continue }

            switch event.type {
            case "content_block_start":
                if let index = event.index, let blockType = event.contentBlock?.type {
                    accumulator.startBlock(
                        index: index,
                        type: blockType,
                        id: event.contentBlock?.id,
                        name: event.contentBlock?.name
                    )
                }
            case "content_block_delta":
                if let index = event.index, let delta = event.delta {
                    if accumulator.isToolUse(at: index) {
                        accumulator.appendDelta(index: index, delta: delta)
                    } else if accumulator.isEmpty,
                              delta.type == "text_delta",
                              let text = delta.text, !text.isEmpty {
                        continuation.yield(.text(text))
                    }
                }
            default:
                break
            }
        }

        // `nil` signals "the model answered with text, which is already streamed".
        // Returning an empty array here would read as `.some([])` at the call site
        // and wrongly continue into the non-streaming tool loop.
        return accumulator.isEmpty ? nil : accumulator.toolCalls
    }

    /// Collects streaming tool-use fragments into complete tool calls.
    private struct ToolCallAccumulator {
        private var blockTypes: [Int: String] = [:]
        private var callsByIndex: [Int: AccumulatingToolCall] = [:]

        var isEmpty: Bool { callsByIndex.isEmpty }

        mutating func startBlock(index: Int, type: String, id: String?, name: String?) {
            blockTypes[index] = type
            if type == "tool_use" {
                callsByIndex[index, default: AccumulatingToolCall()].id = id ?? ""
                callsByIndex[index, default: AccumulatingToolCall()].name = name ?? ""
            }
        }

        func isToolUse(at index: Int) -> Bool {
            blockTypes[index] == "tool_use"
        }

        mutating func appendDelta(index: Int, delta: StreamEvent.Delta) {
            guard delta.type == "input_json_delta", let partialJson = delta.partialJson else { return }
            callsByIndex[index, default: AccumulatingToolCall()].arguments += partialJson
        }

        var toolCalls: [ChatToolCall] {
            callsByIndex
                .sorted { $0.key < $1.key }
                .compactMap { $0.value.chatToolCall }
        }
    }

    private struct AccumulatingToolCall {
        var id: String = ""
        var name: String = ""
        var arguments: String = ""

        var chatToolCall: ChatToolCall? {
            guard !id.isEmpty, !name.isEmpty else { return nil }
            return ChatToolCall(
                id: id,
                name: name,
                argumentsJSON: arguments.isEmpty ? "{}" : arguments
            )
        }
    }

    // MARK: - Encoding

    private static func makeRequest(baseURL: String, apiKey: String?) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL) else {
            throw ChatServiceError.invalidURL
        }
        components.path += components.path.hasSuffix("/") ? "messages" : "/messages"
        guard let url = components.url else {
            throw ChatServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = ChatService.urlSession.configuration.timeoutIntervalForRequest
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        return request
    }

    private static func encodeBody(
        turns: [ChatTurn],
        model: String,
        stream: Bool,
        tools: [ChatToolDefinition],
        reasoningEnabled: Bool?
    ) throws -> Data {
        let systemPrompt = turns
            .filter { $0.role == .system }
            .map(\.content)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let conversationTurns = turns.filter { $0.role != .system }
        let messages = try encodeMessages(conversationTurns)
        let toolPayloads: [ToolPayload]? = tools.isEmpty ? nil : try tools.map(encodeTool)
        let thinking: ThinkingPayload? = (reasoningEnabled == true)
            ? ThinkingPayload(type: "enabled", budgetTokens: 16000)
            : nil

        let body = RequestBody(
            model: model,
            maxTokens: 8192,
            system: systemPrompt.isEmpty ? nil : systemPrompt,
            messages: messages,
            stream: stream,
            tools: toolPayloads,
            thinking: thinking
        )
        return try JSONEncoder().encode(body)
    }

    /// Collapses OpenAI-style tool result turns into Anthropic user `tool_result` blocks.
    private static func encodeMessages(_ turns: [ChatTurn]) throws -> [RequestMessage] {
        var messages: [RequestMessage] = []
        var index = 0
        while index < turns.count {
            let turn = turns[index]
            if turn.role == .tool {
                var results: [AnthropicContentBlock] = []
                while index < turns.count, turns[index].role == .tool {
                    let toolTurn = turns[index]
                    results.append(
                        .toolResult(
                            toolUseID: toolTurn.toolCallID ?? "",
                            content: toolTurn.content
                        )
                    )
                    index += 1
                }
                messages.append(RequestMessage(role: "user", content: .blocks(results)))
                continue
            }

            if turn.hasToolCalls {
                var blocks: [AnthropicContentBlock] = []
                if !turn.content.isEmpty {
                    blocks.append(.text(turn.content))
                }
                for call in turn.toolCalls {
                    let input = try decodeJSONObject(call.argumentsJSON)
                    blocks.append(.toolUse(id: call.id, name: call.name, input: input))
                }
                messages.append(RequestMessage(role: "assistant", content: .blocks(blocks)))
                index += 1
                continue
            }

            messages.append(
                RequestMessage(role: turn.role.rawValue, content: encodeContent(for: turn))
            )
            index += 1
        }
        return messages
    }

    private static func encodeContent(for turn: ChatTurn) -> MessageContent {
        if let parts = MultimodalRequestEncoder.anthropicParts(for: turn) {
            return .blocks(parts.map { part in
                if part.type == "image", let source = part.source {
                    return .image(mediaType: source.mediaType, data: source.data)
                }
                return .text(part.text ?? "")
            })
        }
        return .text(turn.content)
    }

    private static func encodeTool(_ tool: ChatToolDefinition) throws -> ToolPayload {
        let schema = try decodeJSONObject(tool.parametersJSON)
        return ToolPayload(
            name: tool.name,
            description: tool.description,
            inputSchema: schema
        )
    }

    private static func decodeJSONObject(_ json: String) throws -> AnyCodableJSON {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return AnyCodableJSON([String: Any]())
        }
        return AnyCodableJSON(object)
    }

    // MARK: - Wire types

    private struct RequestBody: Encodable {
        var model: String
        var maxTokens: Int
        var system: String?
        var messages: [RequestMessage]
        var stream: Bool
        var tools: [ToolPayload]?
        var thinking: ThinkingPayload?

        enum CodingKeys: String, CodingKey {
            case model, system, messages, stream, tools, thinking
            case maxTokens = "max_tokens"
        }
    }

    private struct ThinkingPayload: Encodable {
        var type: String
        var budgetTokens: Int

        enum CodingKeys: String, CodingKey {
            case type
            case budgetTokens = "budget_tokens"
        }
    }

    private struct RequestMessage: Encodable {
        var role: String
        var content: MessageContent
    }

    private enum MessageContent: Encodable {
        case text(String)
        case blocks([AnthropicContentBlock])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let value):
                try container.encode(value)
            case .blocks(let blocks):
                try container.encode(blocks)
            }
        }
    }

    private enum AnthropicContentBlock: Encodable {
        case text(String)
        case image(mediaType: String, data: String)
        case toolUse(id: String, name: String, input: AnyCodableJSON)
        case toolResult(toolUseID: String, content: String)

        enum CodingKeys: String, CodingKey {
            case type, text, source, id, name, input, content
            case toolUseID = "tool_use_id"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .image(let mediaType, let data):
                try container.encode("image", forKey: .type)
                try container.encode(
                    ["type": "base64", "media_type": mediaType, "data": data],
                    forKey: .source
                )
            case .toolUse(let id, let name, let input):
                try container.encode("tool_use", forKey: .type)
                try container.encode(id, forKey: .id)
                try container.encode(name, forKey: .name)
                try container.encode(input, forKey: .input)
            case .toolResult(let toolUseID, let content):
                try container.encode("tool_result", forKey: .type)
                try container.encode(toolUseID, forKey: .toolUseID)
                try container.encode(content, forKey: .content)
            }
        }
    }

    private struct ToolPayload: Encodable {
        var name: String
        var description: String
        var inputSchema: AnyCodableJSON

        enum CodingKeys: String, CodingKey {
            case name, description
            case inputSchema = "input_schema"
        }
    }

    private struct MessagesResponse: Decodable {
        var content: [ContentBlock]?

        struct ContentBlock: Decodable {
            var type: String
            var text: String?
            var id: String?
            var name: String?
            var input: AnyCodableJSON?
        }
    }

    private struct StreamEvent: Decodable {
        struct Delta: Decodable {
            var type: String?
            var text: String?
            var partialJson: String?

            enum CodingKeys: String, CodingKey {
                case type, text
                case partialJson = "partial_json"
            }
        }
        struct ContentBlock: Decodable {
            var type: String?
            var id: String?
            var name: String?
        }
        var type: String
        var delta: Delta?
        var index: Int?
        var contentBlock: ContentBlock?

        enum CodingKeys: String, CodingKey {
            case type, delta, index
            case contentBlock = "content_block"
        }
    }
}

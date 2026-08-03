import Foundation

/// Speaks the OpenAI `/chat/completions` wire format, which is what the
/// overwhelming majority of hosted and self-hosted models use today:
/// OpenAI, DeepSeek, Qwen (DashScope compatible mode), Kimi/Moonshot,
/// Zhipu GLM, 01.AI Yi, OpenRouter, Google Gemini's OpenAI shim, and any
/// local Ollama / LM Studio / vLLM server.
struct OpenAICompatibleClient: ChatCompletionClient {
    var session: URLSession = .shared

    func streamReply(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        tools: [ChatToolDefinition],
        executeTool: @escaping @Sendable (ChatToolCall) async throws -> String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if tools.isEmpty {
                        try await Self.streamText(
                            turns: turns,
                            model: model,
                            baseURL: baseURL,
                            apiKey: apiKey,
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
                            session: session,
                            continuation: continuation
                        )
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ChatServiceError.cancelled)
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
        session: URLSession,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var workingTurns = turns
        for _ in 0..<WebSearchService.maxToolRounds {
            try Task.checkCancellation()
            let result = try await complete(
                turns: workingTurns,
                model: model,
                baseURL: baseURL,
                apiKey: apiKey,
                tools: tools,
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
                continuation.yield(result.text)
            }
            return
        }

        // Exhausted tool rounds — stream a final answer without tools.
        try await streamText(
            turns: workingTurns,
            model: model,
            baseURL: baseURL,
            apiKey: apiKey,
            session: session,
            continuation: continuation
        )
    }

    // MARK: - Non-streaming completion (tool rounds)

    private static func complete(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        tools: [ChatToolDefinition],
        session: URLSession
    ) async throws -> ChatCompletionResult {
        var request = try makeRequest(baseURL: baseURL, apiKey: apiKey)
        let body = RequestBody(
            model: model,
            messages: turns.map(encodeMessage),
            stream: false,
            tools: tools.isEmpty ? nil : tools.map(encodeTool)
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ChatServiceError.http(status: http.statusCode, body: bodyText)
        }

        let decoded = try JSONDecoder().decode(CompletionResponse.self, from: data)
        guard let message = decoded.choices?.first?.message else {
            throw ChatServiceError.decoding("Missing choices in completion response.")
        }

        let toolCalls = (message.toolCalls ?? []).compactMap { call -> ChatToolCall? in
            guard let id = call.id, let name = call.function?.name else { return nil }
            return ChatToolCall(
                id: id,
                name: name,
                argumentsJSON: call.function?.arguments ?? "{}"
            )
        }
        return ChatCompletionResult(text: message.content ?? "", toolCalls: toolCalls)
    }

    // MARK: - Streaming text (no tools)

    private static func streamText(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        session: URLSession,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var request = try makeRequest(baseURL: baseURL, apiKey: apiKey)
        let body = RequestBody(
            model: model,
            messages: turns.map(encodeMessage),
            stream: true,
            tools: nil
        )
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let upstream = ServerSentEventStream.dataPayloads(for: request, session: session)
        for try await payload in upstream {
            guard let data = payload.data(using: .utf8) else { continue }
            guard let chunk = try? JSONDecoder().decode(Chunk.self, from: data) else { continue }
            if let text = chunk.choices?.first?.delta?.content, !text.isEmpty {
                continuation.yield(text)
            }
        }
    }

    // MARK: - Request helpers

    private static func makeRequest(baseURL: String, apiKey: String?) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL) else {
            throw ChatServiceError.invalidURL
        }
        components.path += components.path.hasSuffix("/") ? "chat/completions" : "/chat/completions"
        guard let url = components.url else {
            throw ChatServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func encodeMessage(_ turn: ChatTurn) -> RequestMessage {
        if turn.role == .tool {
            return RequestMessage(
                role: "tool",
                content: .text(turn.content),
                toolCallID: turn.toolCallID,
                toolCalls: nil
            )
        }

        if turn.hasToolCalls {
            return RequestMessage(
                role: turn.role.rawValue,
                content: turn.content.isEmpty ? .null : .text(turn.content),
                toolCallID: nil,
                toolCalls: turn.toolCalls.map {
                    ToolCallPayload(
                        id: $0.id,
                        type: "function",
                        function: .init(name: $0.name, arguments: $0.argumentsJSON)
                    )
                }
            )
        }

        return RequestMessage(
            role: turn.role.rawValue,
            content: encodeContent(for: turn),
            toolCallID: nil,
            toolCalls: nil
        )
    }

    private static func encodeContent(for turn: ChatTurn) -> MessageContent {
        if let parts = MultimodalRequestEncoder.openAIParts(for: turn) {
            return .parts(parts)
        }
        return .text(turn.content)
    }

    private static func encodeTool(_ tool: ChatToolDefinition) -> ToolPayload {
        let parameters: AnyCodableJSON
        if let data = tool.parametersJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            parameters = AnyCodableJSON(object)
        } else {
            parameters = AnyCodableJSON(["type": "object", "properties": [String: Any]()])
        }
        return ToolPayload(
            type: "function",
            function: .init(
                name: tool.name,
                description: tool.description,
                parameters: parameters
            )
        )
    }

    // MARK: - Wire types

    private struct RequestBody: Encodable {
        var model: String
        var messages: [RequestMessage]
        var stream: Bool
        var tools: [ToolPayload]?
    }

    private struct RequestMessage: Encodable {
        var role: String
        var content: MessageContent
        var toolCallID: String?
        var toolCalls: [ToolCallPayload]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCallID = "tool_call_id"
            case toolCalls = "tool_calls"
        }
    }

    private enum MessageContent: Encodable {
        case text(String)
        case parts([MultimodalRequestEncoder.OpenAIPart])
        case null

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let value):
                try container.encode(value)
            case .parts(let parts):
                try container.encode(parts)
            case .null:
                try container.encodeNil()
            }
        }
    }

    private struct ToolPayload: Encodable {
        var type: String
        var function: FunctionPayload

        struct FunctionPayload: Encodable {
            var name: String
            var description: String
            var parameters: AnyCodableJSON
        }
    }

    private struct ToolCallPayload: Encodable {
        var id: String
        var type: String
        var function: FunctionArgs

        struct FunctionArgs: Encodable {
            var name: String
            var arguments: String
        }
    }

    private struct CompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                var content: String?
                var toolCalls: [ToolCallDTO]?

                enum CodingKeys: String, CodingKey {
                    case content
                    case toolCalls = "tool_calls"
                }
            }
            var message: Message?
        }
        var choices: [Choice]?
    }

    private struct ToolCallDTO: Decodable {
        var id: String?
        var function: FunctionDTO?

        struct FunctionDTO: Decodable {
            var name: String?
            var arguments: String?
        }
    }

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                var content: String?
            }
            var delta: Delta?
        }
        var choices: [Choice]?
    }
}

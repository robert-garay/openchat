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
        executeTool: @escaping @Sendable (ChatToolCall) async throws -> String,
        supportsImageGen: Bool
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if tools.isEmpty {
                        try await Self.streamText(
                            turns: turns,
                            model: model,
                            baseURL: baseURL,
                            apiKey: apiKey,
                            supportsImageGen: supportsImageGen,
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
                            supportsImageGen: supportsImageGen,
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
        supportsImageGen: Bool,
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
            supportsImageGen: supportsImageGen,
            session: session,
            continuation: continuation
        ) {
            workingTurns.append(
                ChatTurn(role: .assistant, content: "", toolCalls: toolCalls)
            )
            for call in toolCalls {
                let output = try await executeTool(call)
                workingTurns.append(
                    ChatTurn(role: .tool, content: output, toolCallID: call.id)
                )
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
                supportsImageGen: supportsImageGen,
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

            try yieldCompletion(result, to: continuation)
            return
        }

        // Exhausted tool rounds — stream a final answer without tools.
        try await streamText(
            turns: workingTurns,
            model: model,
            baseURL: baseURL,
            apiKey: apiKey,
            supportsImageGen: supportsImageGen,
            session: session,
            continuation: continuation
        )
    }

    // MARK: - Non-streaming completion

    private static func yieldCompletion(
        _ result: ChatCompletionResult,
        to continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) throws {
        try Task.checkCancellation()
        var text = result.text
        var images = result.images

        if images.isEmpty {
            let extracted = GeneratedImageParser.extractMarkdownDataURIImages(from: text)
            text = extracted.text
            images = extracted.images
        }

        if !text.isEmpty {
            continuation.yield(.text(text))
        }
        if !images.isEmpty {
            continuation.yield(.images(images))
        }
    }

    private static func complete(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        tools: [ChatToolDefinition],
        supportsImageGen: Bool,
        session: URLSession
    ) async throws -> ChatCompletionResult {
        var request = try makeRequest(baseURL: baseURL, apiKey: apiKey)
        let body = RequestBody(
            model: model,
            messages: turns.map(encodeMessage),
            stream: false,
            tools: tools.isEmpty ? nil : tools.map(encodeTool),
            modalities: supportsImageGen ? ["image", "text"] : nil
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

        var images: [ChatImageAttachment] = []
        for image in message.images ?? [] {
            if let url = image.imageURL?.url,
               let attachment = GeneratedImageParser.attachment(fromDataURI: url) {
                images.append(attachment)
            }
        }
        // Some providers put image parts inside multimodal `content` arrays.
        images.append(contentsOf: message.content.inlineImages)

        return ChatCompletionResult(
            text: message.content.text,
            toolCalls: toolCalls,
            images: images
        )
    }

    // MARK: - Streaming text

    private static func streamText(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        supportsImageGen: Bool,
        session: URLSession,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async throws {
        _ = try await streamText(
            turns: turns,
            model: model,
            baseURL: baseURL,
            apiKey: apiKey,
            tools: [],
            supportsImageGen: supportsImageGen,
            session: session,
            continuation: continuation
        )
    }

    /// Streams a request that may include tools. Returns any tool calls the model emits;
    /// if it returns `nil`, the streamed text (and any images) has already been yielded.
    private static func streamText(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        tools: [ChatToolDefinition],
        supportsImageGen: Bool,
        session: URLSession,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async throws -> [ChatToolCall]? {
        var request = try makeRequest(baseURL: baseURL, apiKey: apiKey)
        let body = RequestBody(
            model: model,
            messages: turns.map(encodeMessage),
            stream: true,
            tools: tools.isEmpty ? nil : tools.map(encodeTool),
            modalities: supportsImageGen ? ["image", "text"] : nil
        )
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        var accumulator = ToolCallAccumulator()

        let upstream = ServerSentEventStream.dataPayloads(for: request, session: session)
        for try await payload in upstream {
            guard let data = payload.data(using: .utf8) else { continue }
            guard let chunk = try? JSONDecoder().decode(Chunk.self, from: data) else { continue }
            let delta = chunk.choices?.first?.delta

            if let toolCallDeltas = delta?.toolCalls, !toolCallDeltas.isEmpty {
                accumulator.append(toolCallDeltas)
                continue
            }

            guard accumulator.isEmpty else {
                // Tool calls already started; ignore any trailing content.
                continue
            }

            if let text = delta?.content.text, !text.isEmpty {
                continuation.yield(.text(text))
            }
            var streamImages: [ChatImageAttachment] = []
            for image in delta?.images ?? [] {
                if let url = image.imageURL?.url,
                   let attachment = GeneratedImageParser.attachment(fromDataURI: url) {
                    streamImages.append(attachment)
                }
            }
            streamImages.append(contentsOf: delta?.content.inlineImages ?? [])
            if !streamImages.isEmpty {
                continuation.yield(.images(streamImages))
            }
        }

        return accumulator.toolCalls
    }

    /// Collects streaming tool-call fragments into complete tool calls.
    private struct ToolCallAccumulator {
        private var callsByIndex: [Int: AccumulatingToolCall] = [:]

        var isEmpty: Bool { callsByIndex.isEmpty }

        mutating func append(_ deltas: [ToolCallDeltaDTO]) {
            for delta in deltas {
                callsByIndex[delta.index, default: AccumulatingToolCall()].append(delta)
            }
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

        mutating func append(_ delta: ToolCallDeltaDTO) {
            if let id = delta.id, !id.isEmpty { self.id = id }
            if let name = delta.function?.name, !name.isEmpty { self.name = name }
            if let arguments = delta.function?.arguments { self.arguments += arguments }
        }

        var chatToolCall: ChatToolCall? {
            guard !id.isEmpty, !name.isEmpty else { return nil }
            return ChatToolCall(
                id: id,
                name: name,
                argumentsJSON: arguments.isEmpty ? "{}" : arguments
            )
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
        request.timeoutInterval = ChatService.urlSession.configuration.timeoutIntervalForRequest
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
        var modalities: [String]?
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
                var content: FlexibleMessageContent
                var toolCalls: [ToolCallDTO]?
                var images: [GeneratedImageDTO]?

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    if container.contains(.content),
                       (try? container.decodeNil(forKey: .content)) != true {
                        content = try container.decode(FlexibleMessageContent.self, forKey: .content)
                    } else {
                        content = FlexibleMessageContent()
                    }
                    toolCalls = try container.decodeIfPresent([ToolCallDTO].self, forKey: .toolCalls)
                    images = try container.decodeIfPresent([GeneratedImageDTO].self, forKey: .images)
                }

                enum CodingKeys: String, CodingKey {
                    case content
                    case toolCalls = "tool_calls"
                    case images
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

    private struct GeneratedImageDTO: Decodable {
        var type: String?
        var imageURL: ImageURLDTO?

        enum CodingKeys: String, CodingKey {
            case type
            case imageURL = "image_url"
        }

        struct ImageURLDTO: Decodable {
            var url: String?
        }
    }

    /// Assistant `content` may be a plain string or a multimodal part array.
    private struct FlexibleMessageContent: Decodable {
        var text: String
        var inlineImages: [ChatImageAttachment]

        init(text: String = "", inlineImages: [ChatImageAttachment] = []) {
            self.text = text
            self.inlineImages = inlineImages
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self.init()
                return
            }
            if let string = try? container.decode(String.self) {
                self.init(text: string)
                return
            }
            let parts = try container.decode([ContentPartDTO].self)
            var textParts: [String] = []
            var images: [ChatImageAttachment] = []
            for part in parts {
                if let partText = part.text, !partText.isEmpty {
                    textParts.append(partText)
                }
                if let url = part.imageURL?.url,
                   let attachment = GeneratedImageParser.attachment(fromDataURI: url) {
                    images.append(attachment)
                }
            }
            self.init(text: textParts.joined(), inlineImages: images)
        }

        private struct ContentPartDTO: Decodable {
            var type: String?
            var text: String?
            var imageURL: GeneratedImageDTO.ImageURLDTO?

            enum CodingKeys: String, CodingKey {
                case type, text
                case imageURL = "image_url"
            }
        }
    }

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                var content: FlexibleMessageContent
                var images: [GeneratedImageDTO]?
                var toolCalls: [ToolCallDeltaDTO]?

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    if container.contains(.content),
                       (try? container.decodeNil(forKey: .content)) != true {
                        content = try container.decode(FlexibleMessageContent.self, forKey: .content)
                    } else {
                        content = FlexibleMessageContent()
                    }
                    images = try container.decodeIfPresent([GeneratedImageDTO].self, forKey: .images)
                    toolCalls = try container.decodeIfPresent([ToolCallDeltaDTO].self, forKey: .toolCalls)
                }

                enum CodingKeys: String, CodingKey {
                    case content, images
                    case toolCalls = "tool_calls"
                }
            }
            var delta: Delta?
        }
        var choices: [Choice]?
    }

    /// A single fragment of a tool call as it arrives in a streaming chunk.
    private struct ToolCallDeltaDTO: Decodable {
        var index: Int
        var id: String?
        var type: String?
        var function: FunctionDeltaDTO?

        struct FunctionDeltaDTO: Decodable {
            var name: String?
            var arguments: String?
        }
    }
}

import Foundation

/// Speaks the OpenAI `/chat/completions` wire format, which is what the
/// overwhelming majority of hosted and self-hosted models use today:
/// OpenAI, DeepSeek, Qwen (DashScope compatible mode), Kimi/Moonshot,
/// Z.ai GLM, 01.AI Yi, OpenRouter, Google Gemini's OpenAI shim, and any
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
        supportsImageGen: Bool,
        effort: EffortLevel?,
        reasoningEnabled: Bool?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        // Belt-and-suspenders: a manually-added custom provider model may have no
        // inferred capabilities at all (no `/models` metadata to infer from), so fall
        // back to the name heuristic here too — this is what actually decides whether
        // the request takes the background-safe non-streaming path below, and a model
        // saved before capability inference existed shouldn't have to be re-added to
        // benefit from it.
        let supportsImageGen = supportsImageGen
            || ModelCapability.inferred(inputModalities: [], outputModalities: [], modelID: model).contains(.imageGen)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if tools.isEmpty, supportsImageGen {
                        // Image generation is a one-shot result with little meaningful text to
                        // stream before it lands, and self-hosted image models can sit silent
                        // for minutes. Use the non-streaming path so the request goes through
                        // `backgroundCompatibleData` (survives app backgrounding, long timeouts)
                        // instead of a plain foreground SSE connection that iOS can suspend or
                        // that an idle-timing-out reverse proxy can drop mid-wait.
                        let result = try await Self.complete(
                            turns: turns,
                            model: model,
                            baseURL: baseURL,
                            apiKey: apiKey,
                            tools: tools,
                            supportsImageGen: supportsImageGen,
                            effort: effort,
                            reasoningEnabled: reasoningEnabled,
                            session: session
                        )
                        try Self.yieldCompletion(result, to: continuation)
                    } else if tools.isEmpty {
                        try await Self.streamText(
                            turns: turns,
                            model: model,
                            baseURL: baseURL,
                            apiKey: apiKey,
                            supportsImageGen: supportsImageGen,
                            effort: effort,
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
                            supportsImageGen: supportsImageGen,
                            effort: effort,
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
        supportsImageGen: Bool,
        effort: EffortLevel?,
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
            supportsImageGen: supportsImageGen,
            effort: effort,
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
                supportsImageGen: supportsImageGen,
                effort: effort,
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
            effort: effort,
            reasoningEnabled: reasoningEnabled,
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
        var images = GeneratedImageDeduper.unique(from: result.images)

        if images.isEmpty {
            let extracted = GeneratedImageParser.extractMarkdownDataURIImages(from: text)
            text = extracted.text
            images = GeneratedImageDeduper.unique(from: extracted.images)
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
        effort: EffortLevel?,
        reasoningEnabled: Bool?,
        session: URLSession
    ) async throws -> ChatCompletionResult {
        var request = try makeRequest(baseURL: baseURL, apiKey: apiKey)
        let body = makeOpenAICompatibleRequestBody(
            model: model,
            messages: turns.map(encodeMessage),
            stream: false,
            tools: tools.isEmpty ? nil : tools.map(encodeTool),
            modalities: supportsImageGen ? ["image", "text"] : nil,
            effort: effort,
            reasoningEnabled: reasoningEnabled,
            baseURL: baseURL
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.backgroundCompatibleData(for: request, retryPolicy: .costSensitive)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ChatServiceError.http(status: http.statusCode, body: bodyText)
        }

        let decoded = try JSONDecoder().decode(OpenAICompletionResponse.self, from: data)
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
        images = GeneratedImageDeduper.unique(from: images)

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
        effort: EffortLevel?,
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
            supportsImageGen: supportsImageGen,
            effort: effort,
            reasoningEnabled: reasoningEnabled,
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
        effort: EffortLevel?,
        reasoningEnabled: Bool?,
        session: URLSession,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async throws -> [ChatToolCall]? {
        var request = try makeRequest(baseURL: baseURL, apiKey: apiKey)
        let body = makeOpenAICompatibleRequestBody(
            model: model,
            messages: turns.map(encodeMessage),
            stream: true,
            tools: tools.isEmpty ? nil : tools.map(encodeTool),
            modalities: supportsImageGen ? ["image", "text"] : nil,
            effort: effort,
            reasoningEnabled: reasoningEnabled,
            baseURL: baseURL
        )
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        var accumulator = OpenAIToolCallAccumulator()

        let upstream = ServerSentEventStream.dataPayloads(for: request, session: session)
        for try await payload in upstream {
            guard let data = payload.data(using: .utf8) else { continue }
            guard let chunk = try? JSONDecoder().decode(OpenAIChunk.self, from: data) else { continue }
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
                continuation.yield(.images(GeneratedImageDeduper.unique(from: streamImages)))
            }
        }

        // `nil` signals "the model answered with text, which is already streamed".
        // Returning an empty array here would read as `.some([])` at the call site
        // and wrongly continue into the non-streaming tool loop.
        return accumulator.isEmpty ? nil : accumulator.toolCalls
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

    private static func encodeMessage(_ turn: ChatTurn) -> OpenAIRequestMessage {
        if turn.role == .tool {
            return OpenAIRequestMessage(
                role: "tool",
                content: .text(turn.content),
                toolCallID: turn.toolCallID,
                toolCalls: nil
            )
        }

        if turn.hasToolCalls {
            return OpenAIRequestMessage(
                role: turn.role.rawValue,
                content: turn.content.isEmpty ? .null : .text(turn.content),
                toolCallID: nil,
                toolCalls: turn.toolCalls.map {
                    OpenAIToolCallPayload(
                        id: $0.id,
                        type: "function",
                        function: .init(name: $0.name, arguments: $0.argumentsJSON)
                    )
                }
            )
        }

        return OpenAIRequestMessage(
            role: turn.role.rawValue,
            content: encodeContent(for: turn),
            toolCallID: nil,
            toolCalls: nil
        )
    }

    private static func encodeContent(for turn: ChatTurn) -> OpenAIMessageContent {
        if let parts = MultimodalRequestEncoder.openAIParts(for: turn) {
            return .parts(parts)
        }
        return .text(turn.content)
    }

    private static func encodeTool(_ tool: ChatToolDefinition) -> OpenAIToolPayload {
        let parameters: AnyCodableJSON
        if let data = tool.parametersJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            parameters = AnyCodableJSON(object)
        } else {
            parameters = AnyCodableJSON(["type": "object", "properties": [String: Any]()])
        }
        return OpenAIToolPayload(
            type: "function",
            function: .init(
                name: tool.name,
                description: tool.description,
                parameters: parameters
            )
        )
    }
}

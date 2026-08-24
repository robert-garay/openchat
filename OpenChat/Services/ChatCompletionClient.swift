import Foundation

protocol ChatCompletionClient: Sendable {
    /// Streams incremental text and/or generated images for one assistant reply.
    /// When `tools` is non-empty, runs a tool-calling loop (non-streaming rounds
    /// until the model returns text, then yields that text).
    /// When `supportsImageGen` is true, requests image output modalities and may
    /// yield `.images` events (typically via a non-streaming completion).
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
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

extension ChatCompletionClient {
    /// Convenience for callers that do not attach tools.
    func streamReply(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        supportsImageGen: Bool = false,
        effort: EffortLevel? = nil,
        reasoningEnabled: Bool? = nil
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        streamReply(
            turns: turns,
            model: model,
            baseURL: baseURL,
            apiKey: apiKey,
            tools: [],
            executeTool: { _ in "" },
            supportsImageGen: supportsImageGen,
            effort: effort,
            reasoningEnabled: reasoningEnabled
        )
    }
}

/// Picks the right wire-format implementation for a configured provider.
enum ChatService {
    /// Dedicated session for chat completions. `URLSession.shared` uses a 60s
    /// request idle timeout, which fails long prompts (slow first token) and
    /// sparse streaming. Self-hosted image models in particular can sit silent
    /// for a long stretch before the first byte, so both timeouts are generous —
    /// a network error here should mean the connection actually died, not that
    /// the model was still working.
    static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 1_800
        configuration.timeoutIntervalForResource = 86_400
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    static func client(for format: APIFormat) -> ChatCompletionClient {
        switch format {
        case .openAI:
            return OpenAICompatibleClient(session: urlSession)
        case .anthropic:
            return AnthropicClient(session: urlSession)
        }
    }
}

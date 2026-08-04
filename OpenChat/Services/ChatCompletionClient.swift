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
        supportsImageGen: Bool
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

extension ChatCompletionClient {
    /// Convenience for callers that do not attach tools.
    func streamReply(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        supportsImageGen: Bool = false
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        streamReply(
            turns: turns,
            model: model,
            baseURL: baseURL,
            apiKey: apiKey,
            tools: [],
            executeTool: { _ in "" },
            supportsImageGen: supportsImageGen
        )
    }
}

/// Picks the right wire-format implementation for a configured provider.
enum ChatService {
    static func client(for format: APIFormat) -> ChatCompletionClient {
        switch format {
        case .openAI:
            return OpenAICompatibleClient()
        case .anthropic:
            return AnthropicClient()
        }
    }
}

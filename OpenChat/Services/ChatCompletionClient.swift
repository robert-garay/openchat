import Foundation

protocol ChatCompletionClient: Sendable {
    /// Streams incremental text deltas for one assistant reply.
    /// When `tools` is non-empty, runs a tool-calling loop (non-streaming rounds
    /// until the model returns text, then yields that text).
    func streamReply(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        tools: [ChatToolDefinition],
        executeTool: @escaping @Sendable (ChatToolCall) async throws -> String
    ) -> AsyncThrowingStream<String, Error>
}

extension ChatCompletionClient {
    /// Convenience for callers that do not attach tools.
    func streamReply(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?
    ) -> AsyncThrowingStream<String, Error> {
        streamReply(turns: turns, model: model, baseURL: baseURL, apiKey: apiKey, tools: []) { _ in
            ""
        }
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

import Foundation

protocol ChatCompletionClient: Sendable {
    /// Streams incremental text deltas for one assistant reply.
    func streamReply(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?
    ) -> AsyncThrowingStream<String, Error>
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

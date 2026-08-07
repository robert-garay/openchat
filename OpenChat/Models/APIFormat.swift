import Foundation

/// The wire format a provider's chat completion endpoint speaks.
/// OpenChat only needs two shapes to cover virtually every hosted or
/// self-hosted model, including every major Chinese open-source model.
enum APIFormat: String, Codable, Hashable, Sendable {
    /// `POST /chat/completions` with `{ model, messages, stream }`.
    /// Used by OpenAI, DeepSeek, Moonshot (Kimi), Z.ai (GLM), Alibaba
    /// Qwen (DashScope compatible mode), 01.AI (Yi), OpenRouter, Google
    /// Gemini's OpenAI-compatible endpoint, and any Ollama / LM Studio /
    /// vLLM style local server.
    case openAI
    /// `POST /messages` with Anthropic's native Claude schema.
    case anthropic
}

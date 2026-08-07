import Foundation

/// A built-in, curated provider definition. Immutable blueprint that a
/// `ConfiguredProvider` is instantiated from. Users can still edit the
/// base URL and model list after adding one (useful for regional API
/// hosts, e.g. Moonshot's `.cn` vs `.ai` domains).
struct ProviderTemplate: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var symbolName: String
    var tint: String
    var baseURL: String
    var apiFormat: APIFormat
    var keyHelpURL: URL?
    var apiKeyPlaceholder: String

    /// Official brand mark in the asset catalog, when available.
    var logoAssetName: String? {
        ProviderLogo.assetName(for: id)
    }

    static let all: [ProviderTemplate] = [
        ProviderTemplate(
            id: "openrouter",
            name: "OpenRouter",
            symbolName: "point.3.connected.trianglepath.dotted",
            tint: "#6467F2",
            baseURL: "https://openrouter.ai/api/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://openrouter.ai/keys"),
            apiKeyPlaceholder: "sk-or-..."
        ),
        ProviderTemplate(
            id: "deepseek",
            name: "DeepSeek",
            symbolName: "sparkles",
            tint: "#4D6BFE",
            baseURL: "https://api.deepseek.com/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://platform.deepseek.com/api_keys"),
            apiKeyPlaceholder: "sk-..."
        ),
        ProviderTemplate(
            id: "qwen",
            name: "Alibaba Cloud",
            symbolName: "wind",
            tint: "#FF6A00",
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://bailian.console.aliyun.com/?apiKey=1"),
            apiKeyPlaceholder: "sk-..."
        ),
        ProviderTemplate(
            id: "moonshot",
            name: "Moonshot AI",
            symbolName: "moon.stars.fill",
            tint: "#16B998",
            baseURL: "https://api.moonshot.cn/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://platform.moonshot.cn/console/api-keys"),
            apiKeyPlaceholder: "sk-..."
        ),
        ProviderTemplate(
            id: "zhipu",
            name: "Z.ai",
            symbolName: "cube.transparent.fill",
            tint: "#3859FF",
            baseURL: "https://api.z.ai/api/paas/v4",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://z.ai/manage-apikey/apikey-list"),
            apiKeyPlaceholder: "API key"
        ),
        ProviderTemplate(
            id: "yi",
            name: "01.AI",
            symbolName: "circle.hexagongrid.fill",
            tint: "#0F172A",
            baseURL: "https://api.lingyiwanwu.com/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://platform.lingyiwanwu.com/apikeys"),
            apiKeyPlaceholder: "API key"
        ),
        ProviderTemplate(
            id: "openai",
            name: "OpenAI",
            symbolName: "brain",
            tint: "#10A37F",
            baseURL: "https://api.openai.com/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://platform.openai.com/api-keys"),
            apiKeyPlaceholder: "sk-..."
        ),
        ProviderTemplate(
            id: "anthropic",
            name: "Anthropic",
            symbolName: "a.circle.fill",
            tint: "#D97757",
            baseURL: "https://api.anthropic.com/v1",
            apiFormat: .anthropic,
            keyHelpURL: URL(string: "https://console.anthropic.com/settings/keys"),
            apiKeyPlaceholder: "sk-ant-..."
        ),
        ProviderTemplate(
            id: "mistral",
            name: "Mistral AI",
            symbolName: "tornado",
            tint: "#FF7000",
            baseURL: "https://api.mistral.ai/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://console.mistral.ai/api-keys/"),
            apiKeyPlaceholder: "API key",
            defaultModels: [
                AIModel(id: "mistral-medium-latest", displayName: "Mistral Medium", subtitle: "Frontier multimodal", capabilities: [.vision, .tools]),
                AIModel(id: "mistral-large-latest", displayName: "Mistral Large", subtitle: "General purpose", capabilities: [.vision, .tools]),
                AIModel(id: "mistral-small-latest", displayName: "Mistral Small", subtitle: "Fast & efficient", capabilities: [.tools]),
                AIModel(id: "pixtral-large-latest", displayName: "Pixtral Large", subtitle: "Vision", capabilities: [.vision, .tools]),
            ]
        ),
        ProviderTemplate(
            id: "google",
            name: "Google",
            symbolName: "diamond.fill",
            tint: "#4285F4",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://aistudio.google.com/apikey"),
            apiKeyPlaceholder: "API key"
        ),
    ]

    static func template(for id: String) -> ProviderTemplate? {
        all.first { $0.id == id }
    }
}

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
    /// Optional catalog endpoint when model discovery lives on a different base
    /// URL than the chat endpoint (OpenCode serves models from `/inference/v1`
    /// but chat from `/inference/openai/v1`).
    var modelsBaseURL: String? = nil
    /// Short terms/usage note shown while adding or editing the provider.
    var usageNote: String? = nil
    /// Headers applied when the provider is added. Users can edit them later.
    var defaultHeaders: [String: String] = [:]
    /// When true, model discovery filters to OpenCode-style `chat-completions` entries.
    var requiresChatCompletionsModelFilter: Bool = false
    /// When true, `x-opencode-session` is injected per chat (or catalog fetch).
    var injectsOpenCodeSession: Bool = false
    /// When true, sends `x-opencode-client: openchat` unless the user overrides it.
    var sendsOpenCodeClientHeader: Bool = false

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
            id: "opencode",
            name: "OpenCode Zen",
            symbolName: "chevron.left.forwardslash.chevron.right",
            tint: "#111827",
            baseURL: "https://opencode.ai/inference/openai/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://opencode.ai/auth"),
            apiKeyPlaceholder: "sk-...",
            modelsBaseURL: "https://opencode.ai/inference/v1",
            defaultHeaders: [
                "x-opencode-client": "openchat",
            ],
            requiresChatCompletionsModelFilter: true,
            injectsOpenCodeSession: true,
            sendsOpenCodeClientHeader: true
        ),
        ProviderTemplate(
            id: "opencode-go",
            name: "OpenCode Go",
            symbolName: "chevron.left.forwardslash.chevron.right",
            tint: "#2563EB",
            baseURL: "https://opencode.ai/inference/go/openai/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://opencode.ai/auth"),
            apiKeyPlaceholder: "sk-...",
            modelsBaseURL: "https://opencode.ai/inference/go/v1",
            usageNote: "OpenCode Go is a coding-agent plan. General chat use may fall outside "
                + "its terms; check OpenCode's usage policy before relying on it for everyday conversations.",
            defaultHeaders: [
                "x-opencode-client": "openchat",
            ],
            requiresChatCompletionsModelFilter: true,
            injectsOpenCodeSession: true,
            sendsOpenCodeClientHeader: true
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
            apiKeyPlaceholder: "API key"
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
        ProviderTemplate(
            id: "cheaperinference",
            name: "Cheaper Inference",
            symbolName: "arrow.down.circle.fill",
            tint: "#16A34A",
            baseURL: "https://api.cheaperinference.com/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://cheaperinference.com/signup"),
            apiKeyPlaceholder: "ir_live_..."
        ),
    ]

    static func template(for id: String) -> ProviderTemplate? {
        all.first { $0.id == id }
    }
}

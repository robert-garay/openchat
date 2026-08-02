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
    var defaultModels: [AIModel]
    var region: String?

    /// Official brand mark in the asset catalog, when available.
    var logoAssetName: String? {
        ProviderLogo.assetName(for: id)
    }

    static let all: [ProviderTemplate] = [
        ProviderTemplate(
            id: "deepseek",
            name: "DeepSeek",
            symbolName: "sparkles",
            tint: "#4D6BFE",
            baseURL: "https://api.deepseek.com/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://platform.deepseek.com/api_keys"),
            apiKeyPlaceholder: "sk-...",
            defaultModels: [
                AIModel(id: "deepseek-chat", displayName: "DeepSeek-V3", subtitle: "General purpose · 64K context"),
                AIModel(id: "deepseek-reasoner", displayName: "DeepSeek-R1", subtitle: "Deep reasoning · 64K context"),
            ],
            region: "China"
        ),
        ProviderTemplate(
            id: "qwen",
            name: "Qwen",
            symbolName: "wind",
            tint: "#615CED",
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://bailian.console.aliyun.com/?apiKey=1"),
            apiKeyPlaceholder: "sk-...",
            defaultModels: [
                AIModel(id: "qwen-max", displayName: "Qwen-Max", subtitle: "Alibaba's flagship model"),
                AIModel(id: "qwen-plus", displayName: "Qwen-Plus", subtitle: "Balanced speed & quality"),
                AIModel(id: "qwen-turbo", displayName: "Qwen-Turbo", subtitle: "Fast & low cost"),
                AIModel(id: "qwen-vl-plus", displayName: "Qwen-VL Plus", subtitle: "Vision", supportsVision: true),
            ],
            region: "China"
        ),
        ProviderTemplate(
            id: "moonshot",
            name: "Kimi (Moonshot AI)",
            symbolName: "moon.stars.fill",
            tint: "#16B998",
            baseURL: "https://api.moonshot.cn/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://platform.moonshot.cn/console/api-keys"),
            apiKeyPlaceholder: "sk-...",
            defaultModels: [
                AIModel(id: "kimi-k2-0711-preview", displayName: "Kimi K2", subtitle: "Frontier open model"),
                AIModel(id: "moonshot-v1-32k", displayName: "Moonshot v1 32K", subtitle: "32K context"),
                AIModel(id: "moonshot-v1-128k", displayName: "Moonshot v1 128K", subtitle: "128K context"),
            ],
            region: "China"
        ),
        ProviderTemplate(
            id: "zhipu",
            name: "Zhipu GLM",
            symbolName: "cube.transparent.fill",
            tint: "#3859FF",
            baseURL: "https://open.bigmodel.cn/api/paas/v4",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://open.bigmodel.cn/usercenter/apikeys"),
            apiKeyPlaceholder: "API key",
            defaultModels: [
                AIModel(id: "glm-4-plus", displayName: "GLM-4-Plus", subtitle: "Flagship reasoning model"),
                AIModel(id: "glm-4-flash", displayName: "GLM-4-Flash", subtitle: "Fast & free tier"),
                AIModel(id: "glm-4v-plus", displayName: "GLM-4V-Plus", subtitle: "Vision", supportsVision: true),
            ],
            region: "China"
        ),
        ProviderTemplate(
            id: "yi",
            name: "01.AI (Yi)",
            symbolName: "circle.hexagongrid.fill",
            tint: "#0F172A",
            baseURL: "https://api.lingyiwanwu.com/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://platform.lingyiwanwu.com/apikeys"),
            apiKeyPlaceholder: "API key",
            defaultModels: [
                AIModel(id: "yi-large", displayName: "Yi-Large", subtitle: "Flagship model"),
                AIModel(id: "yi-large-turbo", displayName: "Yi-Large-Turbo", subtitle: "Faster variant"),
            ],
            region: "China"
        ),
        ProviderTemplate(
            id: "openai",
            name: "OpenAI",
            symbolName: "brain",
            tint: "#10A37F",
            baseURL: "https://api.openai.com/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://platform.openai.com/api-keys"),
            apiKeyPlaceholder: "sk-...",
            defaultModels: [
                AIModel(id: "gpt-5", displayName: "GPT-5", subtitle: "Flagship model", supportsVision: true),
                AIModel(id: "gpt-5-mini", displayName: "GPT-5 Mini", subtitle: "Fast & affordable"),
                AIModel(id: "o4-mini", displayName: "o4-mini", subtitle: "Reasoning model"),
            ]
        ),
        ProviderTemplate(
            id: "anthropic",
            name: "Anthropic",
            symbolName: "a.circle.fill",
            tint: "#D97757",
            baseURL: "https://api.anthropic.com/v1",
            apiFormat: .anthropic,
            keyHelpURL: URL(string: "https://console.anthropic.com/settings/keys"),
            apiKeyPlaceholder: "sk-ant-...",
            defaultModels: [
                AIModel(id: "claude-opus-4-6-20260805", displayName: "Claude Opus 4.6", subtitle: "Most capable", supportsVision: true),
                AIModel(id: "claude-sonnet-4-6-20260805", displayName: "Claude Sonnet 4.6", subtitle: "Balanced", supportsVision: true),
            ]
        ),
        ProviderTemplate(
            id: "google",
            name: "Google Gemini",
            symbolName: "diamond.fill",
            tint: "#4285F4",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://aistudio.google.com/apikey"),
            apiKeyPlaceholder: "API key",
            defaultModels: [
                AIModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro", subtitle: "Flagship", supportsVision: true),
                AIModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", subtitle: "Fast", supportsVision: true),
            ]
        ),
        ProviderTemplate(
            id: "openrouter",
            name: "OpenRouter",
            symbolName: "point.3.connected.trianglepath.dotted",
            tint: "#6467F2",
            baseURL: "https://openrouter.ai/api/v1",
            apiFormat: .openAI,
            keyHelpURL: URL(string: "https://openrouter.ai/keys"),
            apiKeyPlaceholder: "sk-or-...",
            defaultModels: [
                AIModel(id: "deepseek/deepseek-chat", displayName: "DeepSeek-V3", subtitle: "via OpenRouter"),
                AIModel(id: "qwen/qwen-2.5-72b-instruct", displayName: "Qwen 2.5 72B", subtitle: "via OpenRouter"),
                AIModel(id: "moonshotai/kimi-k2", displayName: "Kimi K2", subtitle: "via OpenRouter"),
                AIModel(id: "anthropic/claude-sonnet-4.6", displayName: "Claude Sonnet 4.6", subtitle: "via OpenRouter"),
                AIModel(id: "openai/gpt-5", displayName: "GPT-5", subtitle: "via OpenRouter"),
            ]
        ),
    ]

    static func template(for id: String) -> ProviderTemplate? {
        all.first { $0.id == id }
    }
}

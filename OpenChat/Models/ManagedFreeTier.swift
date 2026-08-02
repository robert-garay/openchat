import Foundation

/// OpenChat-sponsored free access to Qwen3.7 Flash.
/// Backed by a spend-limited OpenRouter API key that is separate from any
/// user BYOK key, so spend can be monitored and capped in the OpenRouter dashboard.
enum ManagedFreeTier {
    static let providerID = "openchat-included"
    static let displayName = "Qwen"
    static let symbolName = "wind"
    static let tint = "#615CED"
    static let baseURL = "https://openrouter.ai/api/v1"

    /// Upstream OpenRouter model id — shown to users under its real name.
    static let openRouterModelID = "qwen/qwen3.7-flash"

    static var model: AIModel {
        AIModel(
            id: openRouterModelID,
            displayName: "Qwen3.7 Flash",
            subtitle: "Free · Vision · 1M context",
            supportsVision: true
        )
    }

    static func makeProvider() -> ConfiguredProvider {
        ConfiguredProvider(
            id: providerID,
            templateID: nil,
            name: displayName,
            symbolName: symbolName,
            tint: tint,
            baseURL: baseURL,
            apiFormat: .openAI,
            models: [model],
            requiresAPIKey: true,
            isEnabled: true
        )
    }
}

extension ConfiguredProvider {
    var isManagedFreeTier: Bool {
        id == ManagedFreeTier.providerID
    }
}

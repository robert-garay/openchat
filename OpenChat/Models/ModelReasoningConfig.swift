import Foundation

/// Reasoning configuration advertised by a provider for a specific model.
/// OpenRouter exposes this in its `/models` response under the `reasoning` key.
/// It tells us which effort levels are allowed, whether reasoning can be disabled,
/// and whether the model uses a separate thinking toggle (e.g. `reasoning.enabled`)
/// rather than encoding "off" as an effort level such as `none`.
struct ModelReasoningConfig: Codable, Hashable, Sendable {
    /// Allowed effort values, usually returned in descending effort order.
    var supportedEfforts: [String]
    /// Default effort when reasoning is enabled.
    var defaultEffort: String?
    /// Whether reasoning is enabled by default.
    var defaultEnabled: Bool
    /// When true, reasoning cannot be disabled and "off" controls should be hidden.
    var isMandatory: Bool
    /// When true, the model accepts a token budget (Anthropic-style) instead of effort.
    var supportsMaxTokens: Bool

    init(
        supportedEfforts: [String] = [],
        defaultEffort: String? = nil,
        defaultEnabled: Bool = false,
        isMandatory: Bool = false,
        supportsMaxTokens: Bool = false
    ) {
        self.supportedEfforts = supportedEfforts
        self.defaultEffort = defaultEffort
        self.defaultEnabled = defaultEnabled
        self.isMandatory = isMandatory
        self.supportsMaxTokens = supportsMaxTokens
    }

    private enum CodingKeys: String, CodingKey {
        case supportedEfforts = "supported_efforts"
        case defaultEffort = "default_effort"
        case defaultEnabled = "default_enabled"
        case isMandatory = "mandatory"
        case supportsMaxTokens = "supports_max_tokens"
    }
}

import Foundation

/// A single model exposed by a provider, e.g. "deepseek-chat" or "claude-opus-4".
struct AIModel: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    /// Short human hint shown under the model name in the picker, e.g. "128K context · Reasoning".
    var subtitle: String?
    /// Capability badges shown next to the model name.
    var capabilities: [ModelCapability]
    /// Provider-reported reasoning configuration, if any. When present it overrides
    /// hardcoded inference for effort levels and thinking-toggle behavior.
    var reasoningConfig: ModelReasoningConfig?

    var supportsVision: Bool {
        capabilities.contains(.vision)
    }

    var supportsImageGen: Bool {
        capabilities.contains(.imageGen)
    }

    var supportsTools: Bool {
        capabilities.contains(.tools)
    }

    var supportsFiles: Bool {
        capabilities.contains(.files)
    }

    var supportsEffort: Bool {
        capabilities.contains(.effort)
    }

    /// The effort levels this model supports, ordered least-to-most reasoning.
    /// Uses the provider-reported configuration when available, otherwise falls back
    /// to hardcoded inference from the model ID/name.
    var supportedEffortLevels: [EffortLevel] {
        guard supportsEffort else { return [] }
        if let config = reasoningConfig, !config.supportedEfforts.isEmpty {
            let reported = Set(config.supportedEfforts.compactMap { EffortLevel(rawValue: $0) })
            return EffortLevel.ordered.filter { reported.contains($0) }
        }
        return EffortLevel.inferred(for: id, modelName: displayName)
    }

    /// True when the model/provider uses a separate thinking/reasoning toggle
    /// (e.g. `reasoning.enabled`, `thinking.type`) rather than encoding "off" as
    /// an effort level such as `none`.
    var hasSeparateThinkingToggle: Bool {
        if let config = reasoningConfig {
            // OpenRouter-style: a separate `reasoning.enabled` toggle exists whenever
            // reasoning is not mandatory.
            return !config.isMandatory
        }
        // Fallback inference for direct providers that expose a separate `thinking` parameter.
        let haystack = "\(id) \(displayName)".lowercased()
        return haystack.contains("deepseek") || haystack.contains("claude") || haystack.contains("anthropic")
    }

    /// True when reasoning cannot be disabled for this model.
    var isReasoningMandatory: Bool {
        reasoningConfig?.isMandatory ?? false
    }

    /// OpenRouter-style `modalities` for chat completions. Nil when omitted (text-only default).
    var chatOutputModalities: [String]? {
        guard supportsImageGen else { return nil }
        return ["image", "text"]
    }

    init(
        id: String,
        displayName: String,
        subtitle: String? = nil,
        supportsVision: Bool = false,
        capabilities: [ModelCapability] = [],
        reasoningConfig: ModelReasoningConfig? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
        self.reasoningConfig = reasoningConfig
        var caps = Set(capabilities)
        if supportsVision { caps.insert(.vision) }
        self.capabilities = ModelCapability.sorted(caps)
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, subtitle, capabilities, supportsVision, reasoningConfig
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        reasoningConfig = try container.decodeIfPresent(ModelReasoningConfig.self, forKey: .reasoningConfig)
        var caps = Set(try container.decodeIfPresent([ModelCapability].self, forKey: .capabilities) ?? [])
        if try container.decodeIfPresent(Bool.self, forKey: .supportsVision) == true {
            caps.insert(.vision)
        }
        capabilities = ModelCapability.sorted(caps)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encodeIfPresent(reasoningConfig, forKey: .reasoningConfig)
    }
}

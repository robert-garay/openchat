import Foundation

/// A single model exposed by a provider, e.g. "deepseek-chat" or "claude-opus-4".
struct AIModel: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    /// Short human hint shown under the model name in the picker, e.g. "128K context · Reasoning".
    var subtitle: String?
    /// Capability badges shown next to the model name.
    var capabilities: [ModelCapability]

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
        capabilities: [ModelCapability] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
        var caps = Set(capabilities)
        if supportsVision { caps.insert(.vision) }
        self.capabilities = ModelCapability.sorted(caps)
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, subtitle, capabilities, supportsVision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
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
    }
}

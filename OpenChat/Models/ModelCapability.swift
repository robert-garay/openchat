import Foundation

/// Compact capability marks shown beside model names in the picker and toolbar.
enum ModelCapability: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    /// Image → text (vision / i2t).
    case vision
    /// Text → image (t2i).
    case imageGen
    /// Audio → text (a2t).
    case audioIn
    /// Text → audio (t2a).
    case audioOut
    /// File/doc → text (f2t).
    case files
    /// Tool / function calling.
    case tools
    /// Internet search / browsing.
    case search
    /// Reasoning / extended thinking.
    case reasoning

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .vision: "eye"
        case .imageGen: "paintbrush.pointed"
        case .audioIn: "waveform"
        case .audioOut: "speaker.wave.2"
        case .files: "doc"
        case .tools: "wrench"
        case .search: "globe"
        case .reasoning: "brain"
        }
    }

    /// Short legend text for the model picker footer.
    var legendLabel: String {
        switch self {
        case .vision: "Reads images"
        case .imageGen: "Makes images"
        case .audioIn: "Hears audio"
        case .audioOut: "Speaks"
        case .files: "Reads files"
        case .tools: "Tools"
        case .search: "Search"
        case .reasoning: "Reasoning"
        }
    }

    var accessibilityLabel: String {
        legendLabel
    }

    /// Stable left-to-right order in the UI.
    static let displayOrder: [ModelCapability] = [
        .vision, .imageGen, .files, .audioIn, .audioOut, .tools, .search, .reasoning
    ]

    static func sorted(_ capabilities: some Sequence<ModelCapability>) -> [ModelCapability] {
        let set = Set(capabilities)
        return displayOrder.filter { set.contains($0) }
    }

    /// Whether `modelCapabilities` includes every capability in `filters`.
    /// An empty filter set matches all models.
    static func matches(_ modelCapabilities: some Sequence<ModelCapability>, filters: Set<ModelCapability>) -> Bool {
        guard !filters.isEmpty else { return true }
        return filters.isSubset(of: Set(modelCapabilities))
    }

    /// Infer badges from OpenRouter modality + parameter metadata.
    static func inferred(
        inputModalities: [String],
        outputModalities: [String],
        supportedParameters: [String] = [],
        modelID: String = "",
        modelName: String = ""
    ) -> [ModelCapability] {
        var caps = Set<ModelCapability>()
        let inputs = Set(inputModalities.map { $0.lowercased() })
        let outputs = Set(outputModalities.map { $0.lowercased() })
        let params = Set(supportedParameters.map { $0.lowercased() })
        let haystack = "\(modelID) \(modelName)".lowercased()

        if inputs.contains("image") { caps.insert(.vision) }
        if outputs.contains("image") { caps.insert(.imageGen) }
        if inputs.contains("audio") { caps.insert(.audioIn) }
        if outputs.contains("audio") { caps.insert(.audioOut) }
        if inputs.contains("file") { caps.insert(.files) }
        if params.contains("tools") { caps.insert(.tools) }
        if params.contains("reasoning") || params.contains("include_reasoning") {
            caps.insert(.reasoning)
        }
        if looksLikeSearchModel(haystack) {
            caps.insert(.search)
        }
        if looksLikeReasoningModel(haystack) {
            caps.insert(.reasoning)
        }

        return sorted(caps)
    }

    private static func looksLikeSearchModel(_ haystack: String) -> Bool {
        let markers = ["sonar", "perplexity", ":online", "-online", "web-search", "websearch", "browsing", "search-preview"]
        return markers.contains { haystack.contains($0) }
    }

    private static func looksLikeReasoningModel(_ haystack: String) -> Bool {
        let markers = ["reasoner", "reasoning", "-r1", "/r1", "o1-", "o3-", "o4-", "thinking", "deepseek-r1"]
        return markers.contains { haystack.contains($0) }
    }
}

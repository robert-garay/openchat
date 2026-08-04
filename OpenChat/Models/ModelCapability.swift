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

    /// Infer badges from modality / parameter metadata, filling gaps from the model identity
    /// when a provider's `/models` payload omits that metadata (common for OpenAI-compatible APIs).
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

        // Naming signals that catalogs rarely encode as modalities.
        if looksLikeSearchModel(haystack) { caps.insert(.search) }
        if looksLikeReasoningModel(haystack) { caps.insert(.reasoning) }

        // OpenAI-compatible `/models` often omits modalities entirely — infer from identity.
        let modalitiesUnknown = inputModalities.isEmpty && outputModalities.isEmpty
        if modalitiesUnknown {
            if looksLikeVisionModel(haystack) { caps.insert(.vision) }
            if looksLikeImageGenModel(haystack) { caps.insert(.imageGen) }
            if looksLikeAudioInModel(haystack) { caps.insert(.audioIn) }
            if looksLikeAudioOutModel(haystack) { caps.insert(.audioOut) }
        }

        // When `supported_parameters` wasn't reported, infer tools for known chat families.
        if supportedParameters.isEmpty, looksLikeToolsModel(haystack) {
            caps.insert(.tools)
        }

        return sorted(caps)
    }

    private static func looksLikeSearchModel(_ haystack: String) -> Bool {
        let markers = ["sonar", "perplexity", ":online", "-online", "web-search", "websearch", "browsing", "search-preview"]
        return markers.contains { haystack.contains($0) }
    }

    private static func looksLikeReasoningModel(_ haystack: String) -> Bool {
        let markers = [
            "reasoner", "reasoning", "-r1", "/r1", "o1-", "o3-", "o4-",
            "thinking", "deepseek-r1", "gpt-5-pro", "gpt-5.pro"
        ]
        return markers.contains { haystack.contains($0) }
    }

    private static func looksLikeVisionModel(_ haystack: String) -> Bool {
        let markers = [
            "gpt-4o", "gpt-4.1", "gpt-4.5", "gpt-4-turbo", "gpt-4-vision", "gpt-5",
            "chatgpt-4o", "o3-", "o4-",
            "claude-3", "claude-4", "claude-opus-4", "claude-sonnet-4", "claude-haiku-4",
            "gemini",
            "-vl", "vl-", "vision", "llava", "pixtral",
            "glm-4v", "llama-4", "maverick", "scout",
            "qwen2.5-vl", "qwen2-vl", "qwen-vl", "qwen3-vl"
        ]
        return markers.contains { haystack.contains($0) }
    }

    private static func looksLikeImageGenModel(_ haystack: String) -> Bool {
        let markers = ["dall-e", "dalle", "gpt-image", "imagen-", "flux-", "stable-diffusion", "black-forest"]
        return markers.contains { haystack.contains($0) }
    }

    private static func looksLikeAudioInModel(_ haystack: String) -> Bool {
        let markers = ["gpt-4o-audio", "gpt-audio", "-audio-", "whisper"]
        return markers.contains { haystack.contains($0) }
    }

    private static func looksLikeAudioOutModel(_ haystack: String) -> Bool {
        let markers = ["gpt-4o-audio", "gpt-audio", "-tts", "tts-", "realtime"]
        return markers.contains { haystack.contains($0) }
    }

    private static func looksLikeToolsModel(_ haystack: String) -> Bool {
        let markers = [
            "gpt-3.5", "gpt-4", "gpt-5", "chatgpt",
            "o1-", "o3-", "o4-",
            "claude", "gemini",
            "deepseek-chat", "deepseek-reasoner", "deepseek-v",
            "qwen", "glm-4", "glm-5", "kimi", "moonshot",
            "yi-large", "yi-lightning",
            "llama-3", "llama-4", "mistral", "mixtral", "command-r"
        ]
        return markers.contains { haystack.contains($0) }
    }
}

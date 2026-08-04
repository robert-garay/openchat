import Foundation

/// A model entry from OpenRouter's live `/models` catalog.
struct OpenRouterCatalogModel: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var created: Int?
    var contextLength: Int?
    var huggingFaceID: String?
    var promptPrice: Double
    var completionPrice: Double
    var modality: String?
    var inputModalities: [String]
    var outputModalities: [String]
    var supportedParameters: [String]
    var isAlias: Bool

    init(
        id: String,
        name: String,
        created: Int? = nil,
        contextLength: Int? = nil,
        huggingFaceID: String? = nil,
        promptPrice: Double,
        completionPrice: Double,
        modality: String? = nil,
        inputModalities: [String],
        outputModalities: [String],
        supportedParameters: [String] = [],
        isAlias: Bool
    ) {
        self.id = id
        self.name = name
        self.created = created
        self.contextLength = contextLength
        self.huggingFaceID = huggingFaceID
        self.promptPrice = promptPrice
        self.completionPrice = completionPrice
        self.modality = modality
        self.inputModalities = inputModalities
        self.outputModalities = outputModalities
        self.supportedParameters = supportedParameters
        self.isAlias = isAlias
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, created, contextLength, huggingFaceID
        case promptPrice, completionPrice, modality
        case inputModalities, outputModalities, supportedParameters, isAlias
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        created = try container.decodeIfPresent(Int.self, forKey: .created)
        contextLength = try container.decodeIfPresent(Int.self, forKey: .contextLength)
        huggingFaceID = try container.decodeIfPresent(String.self, forKey: .huggingFaceID)
        promptPrice = try container.decode(Double.self, forKey: .promptPrice)
        completionPrice = try container.decode(Double.self, forKey: .completionPrice)
        modality = try container.decodeIfPresent(String.self, forKey: .modality)
        inputModalities = try container.decodeIfPresent([String].self, forKey: .inputModalities) ?? []
        outputModalities = try container.decodeIfPresent([String].self, forKey: .outputModalities) ?? []
        supportedParameters = try container.decodeIfPresent([String].self, forKey: .supportedParameters) ?? []
        isAlias = try container.decode(Bool.self, forKey: .isAlias)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(created, forKey: .created)
        try container.encodeIfPresent(contextLength, forKey: .contextLength)
        try container.encodeIfPresent(huggingFaceID, forKey: .huggingFaceID)
        try container.encode(promptPrice, forKey: .promptPrice)
        try container.encode(completionPrice, forKey: .completionPrice)
        try container.encodeIfPresent(modality, forKey: .modality)
        try container.encode(inputModalities, forKey: .inputModalities)
        try container.encode(outputModalities, forKey: .outputModalities)
        try container.encode(supportedParameters, forKey: .supportedParameters)
        try container.encode(isAlias, forKey: .isAlias)
    }

    var isFree: Bool {
        id.hasSuffix(":free") || (promptPrice == 0 && completionPrice == 0)
    }

    var isOpenSource: Bool {
        guard let huggingFaceID else { return false }
        return !huggingFaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var organization: String {
        String(id.split(separator: "/").first ?? Substring(id))
    }

    var displayName: String {
        var value = name
        if let range = value.range(of: ": ") {
            value = String(value[range.upperBound...])
        }
        if value.hasSuffix(" (free)") {
            value = String(value.dropLast(" (free)".count))
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var subtitle: String {
        var parts: [String] = []
        if isOpenSource {
            parts.append("Open source")
        }
        if let contextLength, contextLength > 0 {
            parts.append(Self.formatContext(contextLength))
        }
        return parts.isEmpty ? id : parts.joined(separator: " · ")
    }

    var capabilities: [ModelCapability] {
        ModelCapability.inferred(
            inputModalities: inputModalities,
            outputModalities: outputModalities,
            supportedParameters: supportedParameters,
            modelID: id,
            modelName: name
        )
    }

    var asAIModel: AIModel {
        AIModel(id: id, displayName: displayName, subtitle: subtitle, capabilities: capabilities)
    }

    private static func formatContext(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let millions = Double(tokens) / 1_000_000
            return String(format: millions.rounded() == millions ? "%.0fM context" : "%.1fM context", millions)
        }
        if tokens >= 1_000 {
            return "\(tokens / 1_000)K context"
        }
        return "\(tokens) context"
    }
}

enum OpenRouterModelCatalog {
    static let topFreeCount = 3
    static let topOpenSourceCount = 3

    /// Preferred open-weight orgs, roughly by usefulness for chat apps.
    private static let preferredOpenSourceOrgs = [
        "deepseek",
        "meta-llama",
        "qwen",
        "mistralai",
        "google",
        "moonshotai",
        "openai",
        "z-ai",
        "minimax",
        "nvidia",
    ]

    static func searchableModels(from models: [OpenRouterCatalogModel]) -> [OpenRouterCatalogModel] {
        models
            .filter(isBrowsable)
            .sorted { lhs, rhs in
                if lhs.created != rhs.created {
                    return (lhs.created ?? 0) > (rhs.created ?? 0)
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    static func topFree(from models: [OpenRouterCatalogModel], limit: Int = topFreeCount) -> [OpenRouterCatalogModel] {
        let candidates = searchableModels(from: models)
            .filter(\.isFree)
            .sorted(by: freeRank)
        return diversifyByOrganization(candidates, limit: limit)
    }

    static func topOpenSource(from models: [OpenRouterCatalogModel], limit: Int = topOpenSourceCount) -> [OpenRouterCatalogModel] {
        let candidates = searchableModels(from: models)
            .filter { $0.isOpenSource && !$0.isFree }
            .sorted(by: openSourceRank)
        return diversifyByOrganization(candidates, limit: limit)
    }

    private static func diversifyByOrganization(
        _ candidates: [OpenRouterCatalogModel],
        limit: Int
    ) -> [OpenRouterCatalogModel] {
        var picked: [OpenRouterCatalogModel] = []
        var seenOrgs = Set<String>()

        for model in candidates {
            let org = model.organization.lowercased()
            if seenOrgs.contains(org) { continue }
            seenOrgs.insert(org)
            picked.append(model)
            if picked.count == limit { break }
        }

        if picked.count < limit {
            for model in candidates where !picked.contains(model) {
                picked.append(model)
                if picked.count == limit { break }
            }
        }

        return picked
    }

    static func filtered(
        models: [OpenRouterCatalogModel],
        query: String,
        capabilities: Set<ModelCapability> = []
    ) -> [OpenRouterCatalogModel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var results = searchableModels(from: models)
        if !trimmed.isEmpty {
            results = results.filter {
                $0.id.localizedCaseInsensitiveContains(trimmed) ||
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.displayName.localizedCaseInsensitiveContains(trimmed) ||
                $0.organization.localizedCaseInsensitiveContains(trimmed)
            }
        }
        if !capabilities.isEmpty {
            results = results.filter {
                ModelCapability.matches($0.capabilities, filters: capabilities)
            }
        }
        return results
    }

    private static func isBrowsable(_ model: OpenRouterCatalogModel) -> Bool {
        guard !model.isAlias else { return false }
        guard !model.id.hasPrefix("~") else { return false }
        guard model.id != "openrouter/free" else { return false }
        let hasTextOut = model.outputModalities.contains("text") || (model.modality?.contains("->text") == true)
        let hasImageOut = model.outputModalities.contains("image") || (model.modality?.contains("->image") == true)
        guard hasTextOut || hasImageOut else { return false }
        let lowered = model.id.lowercased()
        if lowered.contains("lyria") || lowered.contains("content-safety") {
            return false
        }
        return true
    }

    private static func freeRank(_ lhs: OpenRouterCatalogModel, _ rhs: OpenRouterCatalogModel) -> Bool {
        let lhsSuffix = lhs.id.hasSuffix(":free")
        let rhsSuffix = rhs.id.hasSuffix(":free")
        if lhsSuffix != rhsSuffix { return lhsSuffix && !rhsSuffix }

        if lhs.contextLength != rhs.contextLength {
            return (lhs.contextLength ?? 0) > (rhs.contextLength ?? 0)
        }

        let lhsPref = preferredOrgIndex(lhs.organization)
        let rhsPref = preferredOrgIndex(rhs.organization)
        if lhsPref != rhsPref { return lhsPref < rhsPref }

        return (lhs.created ?? 0) > (rhs.created ?? 0)
    }

    private static func openSourceRank(_ lhs: OpenRouterCatalogModel, _ rhs: OpenRouterCatalogModel) -> Bool {
        let lhsPref = preferredOrgIndex(lhs.organization)
        let rhsPref = preferredOrgIndex(rhs.organization)
        if lhsPref != rhsPref { return lhsPref < rhsPref }

        let lhsDated = looksDated(lhs.id)
        let rhsDated = looksDated(rhs.id)
        if lhsDated != rhsDated { return !lhsDated && rhsDated }

        if lhs.contextLength != rhs.contextLength {
            return (lhs.contextLength ?? 0) > (rhs.contextLength ?? 0)
        }
        return (lhs.created ?? 0) > (rhs.created ?? 0)
    }

    private static func preferredOrgIndex(_ organization: String) -> Int {
        let lowered = organization.lowercased()
        if let index = preferredOpenSourceOrgs.firstIndex(of: lowered) {
            return index
        }
        return preferredOpenSourceOrgs.count + 1
    }

    private static func looksDated(_ id: String) -> Bool {
        id.range(of: #"\d{4}"#, options: .regularExpression) != nil
            || id.range(of: #"-\d{4}"#, options: .regularExpression) != nil
            || id.contains("-exp")
            || id.contains("preview")
    }
}

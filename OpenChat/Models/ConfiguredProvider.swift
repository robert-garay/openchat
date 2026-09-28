import Foundation

/// A provider the user has actually added to the app. Non-secret fields are
/// persisted to `UserDefaults` as JSON; the API key itself lives in the
/// Keychain, keyed by `id`. This is what shows up in Settings and feeds the
/// model picker.
struct ConfiguredProvider: Codable, Identifiable, Hashable, Sendable {
    var id: String
    /// nil for a fully custom, user-defined endpoint (e.g. Ollama).
    var templateID: String?
    var name: String
    var symbolName: String
    var tint: String
    var baseURL: String
    var apiFormat: APIFormat
    var models: [AIModel]
    /// Some local servers (Ollama, LM Studio) don't require a key at all.
    var requiresAPIKey: Bool
    var isEnabled: Bool
    /// User-picked brand mark (see `CustomEndpointLogoOption`) for a custom endpoint.
    /// Purely cosmetic; nil falls back to the generic server icon.
    var customLogoID: String? = nil
    /// On-device MLX uses `.localMLX`; cloud and LAN endpoints use `.remoteHTTP`.
    var inferenceBackend: InferenceBackend = .remoteHTTP

    var usesLocalInference: Bool {
        inferenceBackend == .localMLX
    }

    init(
        id: String,
        templateID: String?,
        name: String,
        symbolName: String,
        tint: String,
        baseURL: String,
        apiFormat: APIFormat,
        models: [AIModel],
        requiresAPIKey: Bool,
        isEnabled: Bool,
        customLogoID: String? = nil,
        inferenceBackend: InferenceBackend = .remoteHTTP
    ) {
        self.id = id
        self.templateID = templateID
        self.name = name
        self.symbolName = symbolName
        self.tint = tint
        self.baseURL = baseURL
        self.apiFormat = apiFormat
        self.models = models
        self.requiresAPIKey = requiresAPIKey
        self.isEnabled = isEnabled
        self.customLogoID = customLogoID
        self.inferenceBackend = inferenceBackend
    }

    var template: ProviderTemplate? {
        templateID.flatMap(ProviderTemplate.template(for:))
    }

    /// Official brand mark in the asset catalog, resolved from the template, a
    /// user-picked custom logo, or the provider id.
    var logoAssetName: String? {
        ProviderLogo.assetName(for: templateID)
            ?? CustomEndpointLogoOption.option(for: customLogoID)?.logoAssetName
            ?? ProviderLogo.assetName(for: id)
    }

    static func fromTemplate(_ template: ProviderTemplate) -> ConfiguredProvider {
        ConfiguredProvider(
            id: template.id,
            templateID: template.id,
            name: template.name,
            symbolName: template.symbolName,
            tint: template.tint,
            baseURL: template.baseURL,
            apiFormat: template.apiFormat,
            models: [],
            requiresAPIKey: true,
            isEnabled: true
        )
    }

    static func customEndpoint(
        name: String,
        baseURL: String,
        models: [AIModel],
        requiresAPIKey: Bool,
        logoID: String? = nil
    ) -> ConfiguredProvider {
        ConfiguredProvider(
            id: "custom-\(UUID().uuidString.prefix(8))",
            templateID: nil,
            name: name,
            symbolName: "server.rack",
            tint: "#8E8E93",
            baseURL: baseURL,
            apiFormat: .openAI,
            models: models,
            requiresAPIKey: requiresAPIKey,
            isEnabled: true,
            customLogoID: logoID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, templateID, name, symbolName, tint, baseURL, apiFormat, models
        case requiresAPIKey, isEnabled, customLogoID, inferenceBackend
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        templateID = try container.decodeIfPresent(String.self, forKey: .templateID)
        name = try container.decode(String.self, forKey: .name)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        tint = try container.decode(String.self, forKey: .tint)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        apiFormat = try container.decode(APIFormat.self, forKey: .apiFormat)
        models = try container.decode([AIModel].self, forKey: .models)
        requiresAPIKey = try container.decode(Bool.self, forKey: .requiresAPIKey)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        customLogoID = try container.decodeIfPresent(String.self, forKey: .customLogoID)
        inferenceBackend = try container.decodeIfPresent(InferenceBackend.self, forKey: .inferenceBackend) ?? .remoteHTTP
    }
}

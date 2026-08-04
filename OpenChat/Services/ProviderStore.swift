import Foundation
import Observation

/// Masks an API key for display, keeping a short prefix and suffix so the
/// user can recognize which key is configured without revealing the secret.
enum APIKeyRedaction {
    static func redacted(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // Short keys would leak too much if any characters stayed visible.
        guard trimmed.count > 8 else {
            return String(repeating: "•", count: 8)
        }
        let prefix = String(trimmed.prefix(3))
        let suffix = String(trimmed.suffix(4))
        return prefix + String(repeating: "•", count: 8) + suffix
    }
}

/// Owns the list of providers the user has configured and their API keys.
/// Non-secret provider metadata is persisted as JSON in `UserDefaults`;
/// API keys live in the Keychain via `KeychainStore`.
@MainActor
@Observable
final class ProviderStore {
    private(set) var providers: [ConfiguredProvider] = []
    private(set) var openRouterModels: [OpenRouterCatalogModel] = []
    private(set) var isLoadingOpenRouterModels = false
    private(set) var openRouterModelsError: String?
    /// Live catalogs for non-OpenRouter providers, keyed by provider id.
    private(set) var liveModelsByProviderID: [String: [AIModel]] = [:]
    private(set) var loadingModelProviderIDs: Set<String> = []
    private(set) var liveModelErrors: [String: String] = [:]

    private let defaultsKey = "com.openchat.configuredProviders"
    private let openRouterCacheKey = "com.openchat.openRouterModelsCache"
    private let openRouterCacheDateKey = "com.openchat.openRouterModelsCacheDate"
    private let liveModelsCacheKeyPrefix = "com.openchat.liveModels."
    private let liveModelsCacheDateKeyPrefix = "com.openchat.liveModelsDate."
    private let modelsCacheTTL: TimeInterval = 60 * 60
    private let defaults: UserDefaults
    private let openRouterClient: OpenRouterModelsClient
    private let modelsClient: ProviderModelsClient
    private var modelRefreshTasks: [String: Task<Void, Never>] = [:]
    /// Bumped when Keychain-backed credentials change so Observation can refresh views.
    private var credentialsEpoch = 0

    init(
        defaults: UserDefaults = .standard,
        openRouterClient: OpenRouterModelsClient = OpenRouterModelsClient(),
        modelsClient: ProviderModelsClient = ProviderModelsClient()
    ) {
        self.defaults = defaults
        self.openRouterClient = openRouterClient
        self.modelsClient = modelsClient
        load()
        loadOpenRouterCache()
        loadLiveModelCaches()
    }

    var enabledProviders: [ConfiguredProvider] {
        providers.filter { $0.isEnabled && hasUsableCredentials($0) }
    }

    var isLoadingModels: Bool {
        isLoadingOpenRouterModels || !loadingModelProviderIDs.isEmpty
    }

    func hasUsableCredentials(_ provider: ConfiguredProvider) -> Bool {
        !provider.requiresAPIKey || apiKey(for: provider) != nil
    }

    func apiKey(for provider: ConfiguredProvider) -> String? {
        _ = credentialsEpoch
        let key = KeychainStore.get(provider.id)
        return (key?.isEmpty ?? true) ? nil : key
    }

    /// Redacted key for Settings rows, or `nil` when no key is stored.
    func redactedAPIKey(for provider: ConfiguredProvider) -> String? {
        guard let key = apiKey(for: provider) else { return nil }
        return APIKeyRedaction.redacted(key)
    }

    func setAPIKey(_ apiKey: String, for provider: ConfiguredProvider) {
        KeychainStore.set(apiKey, forKey: provider.id)
        credentialsEpoch &+= 1
    }

    func removeAPIKey(for provider: ConfiguredProvider) {
        KeychainStore.remove(provider.id)
        credentialsEpoch &+= 1
    }

    func addFromTemplate(_ template: ProviderTemplate) {
        guard !providers.contains(where: { $0.id == template.id }) else { return }
        providers.append(.fromTemplate(template))
        persist()
    }

    func addCustom(name: String, baseURL: String, models: [AIModel], requiresAPIKey: Bool) {
        providers.append(.customEndpoint(name: name, baseURL: baseURL, models: models, requiresAPIKey: requiresAPIKey))
        persist()
    }

    func update(_ provider: ConfiguredProvider) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[index] = provider
        persist()
    }

    func remove(_ provider: ConfiguredProvider) {
        providers.removeAll { $0.id == provider.id }
        removeAPIKey(for: provider)
        liveModelsByProviderID[provider.id] = nil
        liveModelErrors[provider.id] = nil
        loadingModelProviderIDs.remove(provider.id)
        modelRefreshTasks[provider.id]?.cancel()
        modelRefreshTasks[provider.id] = nil
        defaults.removeObject(forKey: liveModelsCacheKey(for: provider.id))
        defaults.removeObject(forKey: liveModelsCacheDateKey(for: provider.id))
        persist()
    }

    func provider(withID id: String) -> ConfiguredProvider? {
        providers.first { $0.id == id }
    }

    func model(providerID: String, modelID: String) -> AIModel? {
        if let saved = provider(withID: providerID)?.models.first(where: { $0.id == modelID }) {
            return saved
        }
        if providerID == "openrouter" {
            return openRouterModels.first(where: { $0.id == modelID })?.asAIModel
        }
        return liveModelsByProviderID[providerID]?.first(where: { $0.id == modelID })
    }

    /// Models shown in the picker for a non-OpenRouter provider.
    /// Prefers the live catalog, falling back to saved/default models.
    func pickerModels(for provider: ConfiguredProvider) -> [AIModel] {
        if let live = liveModelsByProviderID[provider.id], !live.isEmpty {
            return live
        }
        return provider.models
    }

    /// Keeps selections usable after the picker closes by persisting the chosen model.
    func rememberModel(_ model: AIModel, providerID: String) {
        guard var provider = provider(withID: providerID) else { return }
        if let index = provider.models.firstIndex(where: { $0.id == model.id }) {
            provider.models[index] = model
        } else {
            provider.models.insert(model, at: 0)
        }
        update(provider)
    }

    /// Keeps OpenRouter selections usable after the picker closes by persisting
    /// the chosen catalog entry onto the configured provider.
    func rememberOpenRouterModel(_ model: OpenRouterCatalogModel) {
        rememberModel(model.asAIModel, providerID: "openrouter")
    }

    /// Refresh live catalogs for every enabled provider.
    func refreshModelsIfNeeded(force: Bool = false) {
        for provider in enabledProviders {
            if provider.id == "openrouter" {
                refreshOpenRouterModelsIfNeeded(force: force)
            } else {
                refreshProviderModelsIfNeeded(provider, force: force)
            }
        }
    }

    func refreshOpenRouterModelsIfNeeded(force: Bool = false) {
        guard enabledProviders.contains(where: { $0.id == "openrouter" }) else { return }

        if !force,
           !openRouterModels.isEmpty,
           let cachedAt = defaults.object(forKey: openRouterCacheDateKey) as? Date,
           Date().timeIntervalSince(cachedAt) < modelsCacheTTL {
            return
        }

        modelRefreshTasks["openrouter"]?.cancel()
        modelRefreshTasks["openrouter"] = Task { [weak self] in
            await self?.fetchOpenRouterModels()
        }
    }

    private func refreshProviderModelsIfNeeded(_ provider: ConfiguredProvider, force: Bool) {
        if !force,
           let cached = liveModelsByProviderID[provider.id], !cached.isEmpty,
           let cachedAt = defaults.object(forKey: liveModelsCacheDateKey(for: provider.id)) as? Date,
           Date().timeIntervalSince(cachedAt) < modelsCacheTTL {
            return
        }

        modelRefreshTasks[provider.id]?.cancel()
        modelRefreshTasks[provider.id] = Task { [weak self] in
            await self?.fetchProviderModels(provider)
        }
    }

    private func fetchOpenRouterModels() async {
        isLoadingOpenRouterModels = true
        openRouterModelsError = nil

        do {
            let models = try await openRouterClient.fetchModels()
            guard !Task.isCancelled else { return }
            openRouterModels = models
            persistOpenRouterCache(models)
            isLoadingOpenRouterModels = false
        } catch {
            guard !Task.isCancelled else { return }
            if openRouterModels.isEmpty {
                openRouterModelsError = error.localizedDescription
            }
            isLoadingOpenRouterModels = false
        }
    }

    private func fetchProviderModels(_ provider: ConfiguredProvider) async {
        loadingModelProviderIDs.insert(provider.id)
        liveModelErrors[provider.id] = nil

        do {
            let fetched = try await modelsClient.fetchModels(
                for: provider,
                apiKey: apiKey(for: provider)
            )
            guard !Task.isCancelled else { return }
            let models = ProviderModelsClient.enrich(fetched, using: provider.models)
            liveModelsByProviderID[provider.id] = models
            persistLiveModelsCache(models, providerID: provider.id)
            loadingModelProviderIDs.remove(provider.id)
        } catch {
            guard !Task.isCancelled else { return }
            if liveModelsByProviderID[provider.id]?.isEmpty ?? true {
                liveModelErrors[provider.id] = error.localizedDescription
            }
            loadingModelProviderIDs.remove(provider.id)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ConfiguredProvider].self, from: data) else {
            return
        }
        providers = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func loadOpenRouterCache() {
        guard let data = defaults.data(forKey: openRouterCacheKey),
              let decoded = try? JSONDecoder().decode([OpenRouterCatalogModel].self, from: data) else {
            return
        }
        openRouterModels = decoded
    }

    private func persistOpenRouterCache(_ models: [OpenRouterCatalogModel]) {
        guard let data = try? JSONEncoder().encode(models) else { return }
        defaults.set(data, forKey: openRouterCacheKey)
        defaults.set(Date(), forKey: openRouterCacheDateKey)
    }

    private func loadLiveModelCaches() {
        for provider in providers where provider.id != "openrouter" {
            let key = liveModelsCacheKey(for: provider.id)
            guard let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([AIModel].self, from: data) else {
                continue
            }
            liveModelsByProviderID[provider.id] = decoded
        }
    }

    private func persistLiveModelsCache(_ models: [AIModel], providerID: String) {
        guard let data = try? JSONEncoder().encode(models) else { return }
        defaults.set(data, forKey: liveModelsCacheKey(for: providerID))
        defaults.set(Date(), forKey: liveModelsCacheDateKey(for: providerID))
    }

    private func liveModelsCacheKey(for providerID: String) -> String {
        liveModelsCacheKeyPrefix + providerID
    }

    private func liveModelsCacheDateKey(for providerID: String) -> String {
        liveModelsCacheDateKeyPrefix + providerID
    }
}

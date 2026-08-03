import Foundation
import Observation

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

    private let defaultsKey = "com.openchat.configuredProviders"
    private let openRouterCacheKey = "com.openchat.openRouterModelsCache"
    private let openRouterCacheDateKey = "com.openchat.openRouterModelsCacheDate"
    private let openRouterCacheTTL: TimeInterval = 60 * 60
    private let defaults: UserDefaults
    private let openRouterClient: OpenRouterModelsClient
    private var openRouterRefreshTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        openRouterClient: OpenRouterModelsClient = OpenRouterModelsClient()
    ) {
        self.defaults = defaults
        self.openRouterClient = openRouterClient
        load()
        loadOpenRouterCache()
    }

    var enabledProviders: [ConfiguredProvider] {
        providers.filter { $0.isEnabled && hasUsableCredentials($0) }
    }

    func hasUsableCredentials(_ provider: ConfiguredProvider) -> Bool {
        !provider.requiresAPIKey || apiKey(for: provider) != nil
    }

    func apiKey(for provider: ConfiguredProvider) -> String? {
        let key = KeychainStore.get(provider.id)
        return (key?.isEmpty ?? true) ? nil : key
    }

    func setAPIKey(_ apiKey: String, for provider: ConfiguredProvider) {
        KeychainStore.set(apiKey, forKey: provider.id)
    }

    func removeAPIKey(for provider: ConfiguredProvider) {
        KeychainStore.remove(provider.id)
    }

    func addFromTemplate(_ template: ProviderTemplate) {
        guard !providers.contains(where: { $0.id == template.id }) else { return }
        providers.append(.fromTemplate(template))
        persist()
    }

    /// Connects OpenRouter with starter models and stores the API key.
    func connectOpenRouter(apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let template = ProviderTemplate.template(for: "openrouter") else { return }

        let starterModels = ProviderTemplate.openRouterStarterModels
        if var existing = provider(withID: "openrouter") {
            mergeModels(starterModels, into: &existing, atFront: true)
            update(existing)
        } else {
            var provider = ConfiguredProvider.fromTemplate(template)
            provider.models = starterModels.isEmpty ? template.defaultModels : starterModels
            providers.append(provider)
            persist()
        }

        guard let openRouter = provider(withID: "openrouter") else { return }
        setAPIKey(trimmed, for: openRouter)
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
        return nil
    }

    /// Keeps OpenRouter selections usable after the picker closes by persisting
    /// the chosen catalog entry onto the configured provider.
    func rememberOpenRouterModel(_ model: OpenRouterCatalogModel) {
        guard var provider = provider(withID: "openrouter") else { return }
        if let index = provider.models.firstIndex(where: { $0.id == model.id }) {
            provider.models[index] = model.asAIModel
        } else {
            provider.models.insert(model.asAIModel, at: 0)
        }
        update(provider)
    }

    func refreshOpenRouterModelsIfNeeded(force: Bool = false) {
        guard enabledProviders.contains(where: { $0.id == "openrouter" }) else { return }

        if !force,
           !openRouterModels.isEmpty,
           let cachedAt = defaults.object(forKey: openRouterCacheDateKey) as? Date,
           Date().timeIntervalSince(cachedAt) < openRouterCacheTTL {
            return
        }

        openRouterRefreshTask?.cancel()
        openRouterRefreshTask = Task { [weak self] in
            await self?.fetchOpenRouterModels()
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
            syncOpenRouterStarterModels()
            isLoadingOpenRouterModels = false
        } catch {
            guard !Task.isCancelled else { return }
            if openRouterModels.isEmpty {
                openRouterModelsError = error.localizedDescription
            }
            isLoadingOpenRouterModels = false
        }
    }

    /// Replaces the in-memory OpenRouter catalog. Used by tests and local tooling.
    func replaceOpenRouterModels(_ models: [OpenRouterCatalogModel]) {
        openRouterModels = models
    }

    /// Keeps starter OpenRouter models present on the configured provider.
    func syncOpenRouterStarterModels() {
        guard var provider = provider(withID: "openrouter") else { return }
        let starters = ProviderTemplate.openRouterStarterModels
        guard !starters.isEmpty else { return }

        var didChange = false
        let existingIDs = Set(provider.models.map(\.id))
        for model in starters.reversed() where !existingIDs.contains(model.id) {
            provider.models.insert(model, at: 0)
            didChange = true
        }
        if didChange {
            update(provider)
        }
    }

    private func mergeModels(_ incoming: [AIModel], into provider: inout ConfiguredProvider, atFront: Bool) {
        for model in incoming.reversed() {
            if let index = provider.models.firstIndex(where: { $0.id == model.id }) {
                provider.models[index] = model
                if atFront && index != 0 {
                    provider.models.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
                }
            } else if atFront {
                provider.models.insert(model, at: 0)
            } else {
                provider.models.append(model)
            }
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
}

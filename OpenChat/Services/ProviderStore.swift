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

    private let defaultsKey = "com.openchat.configuredProviders"
    private let openRouterCacheKey = "com.openchat.openRouterModelsCache"
    private let openRouterCacheDateKey = "com.openchat.openRouterModelsCacheDate"
    private let openRouterCacheTTL: TimeInterval = 60 * 60
    private let defaults: UserDefaults
    private let openRouterClient: OpenRouterModelsClient
    private var openRouterRefreshTask: Task<Void, Never>?
    /// Bumped when Keychain-backed credentials change so Observation can refresh views.
    private var credentialsEpoch = 0

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
            isLoadingOpenRouterModels = false
        } catch {
            guard !Task.isCancelled else { return }
            if openRouterModels.isEmpty {
                openRouterModelsError = error.localizedDescription
            }
            isLoadingOpenRouterModels = false
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

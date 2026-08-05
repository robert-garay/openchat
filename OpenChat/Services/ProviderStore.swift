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
    private let modelUsageCountsKey = "com.openchat.modelUsageCounts"
    private let modelUsageSeededKey = "com.openchat.modelUsageSeeded"
    private let lastSelectedModelKey = "com.openchat.lastSelectedModel"
    private let starredModelsKey = "com.openchat.starredModels"
    private let modelsCacheTTL: TimeInterval = 60 * 60
    private let defaults: UserDefaults
    private let openRouterClient: OpenRouterModelsClient
    private let modelsClient: ProviderModelsClient
    private var modelRefreshTasks: [String: Task<Void, Never>] = [:]
    /// Bumped when Keychain-backed credentials change so Observation can refresh views.
    private var credentialsEpoch = 0
    /// Selection frequency keyed by `providerID/modelID` for picker ranking.
    private(set) var modelUsageCounts: [String: Int] = [:]
    /// Last model the user explicitly set in any conversation (`providerID/modelID`).
    private(set) var lastSelectedModelUsageKey: String?
    /// Starred models keyed by `providerID/modelID`; pinned to the top of the unfiltered picker.
    private(set) var starredModelKeys: Set<String> = []

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
        loadModelUsageCounts()
        loadLastSelectedModel()
        loadStarredModels()
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

    /// Stable key for a provider/model pair in usage maps.
    static func modelUsageKey(providerID: String, modelID: String) -> String {
        "\(providerID)/\(modelID)"
    }

    func modelUsageCount(providerID: String, modelID: String) -> Int {
        modelUsageCounts[Self.modelUsageKey(providerID: providerID, modelID: modelID)] ?? 0
    }

    /// Bumps the selection count when the user chooses a model.
    func recordModelUsage(providerID: String, modelID: String) {
        let key = Self.modelUsageKey(providerID: providerID, modelID: modelID)
        modelUsageCounts[key, default: 0] += 1
        persistModelUsageCounts()
        rememberLastSelectedModel(providerID: providerID, modelID: modelID)
    }

    /// Last model the user set, if that provider/model is still available.
    var lastSelectedModel: (providerID: String, modelID: String)? {
        guard let key = lastSelectedModelUsageKey else { return nil }
        let parts = key.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return (providerID: String(parts[0]), modelID: String(parts[1]))
    }

    /// Remembers the model for the next new chat. Existing chats keep their own stored model.
    func rememberLastSelectedModel(providerID: String, modelID: String) {
        let key = Self.modelUsageKey(providerID: providerID, modelID: modelID)
        guard lastSelectedModelUsageKey != key else { return }
        lastSelectedModelUsageKey = key
        defaults.set(key, forKey: lastSelectedModelKey)
    }

    /// One-time bootstrap from the most recently updated conversation when nothing is stored yet.
    func seedLastSelectedModelIfNeeded(providerID: String, modelID: String) {
        guard lastSelectedModelUsageKey == nil else { return }
        rememberLastSelectedModel(providerID: providerID, modelID: modelID)
    }

    /// Provider/model pair to use when creating a new chat.
    func defaultModelForNewChat() -> (providerID: String, modelID: String)? {
        if let last = lastSelectedModel,
           enabledProviders.contains(where: { $0.id == last.providerID }),
           model(providerID: last.providerID, modelID: last.modelID) != nil {
            return last
        }
        guard let provider = enabledProviders.first,
              let model = provider.models.first else {
            return nil
        }
        return (providerID: provider.id, modelID: model.id)
    }

    func isModelStarred(providerID: String, modelID: String) -> Bool {
        starredModelKeys.contains(Self.modelUsageKey(providerID: providerID, modelID: modelID))
    }

    func toggleStarredModel(providerID: String, modelID: String) {
        let key = Self.modelUsageKey(providerID: providerID, modelID: modelID)
        var next = starredModelKeys
        if next.contains(key) {
            next.remove(key)
        } else {
            next.insert(key)
        }
        starredModelKeys = next
        persistStarredModels()
    }

    /// One-time seed from existing chats so ranking is useful before any new picks.
    func seedModelUsageFromConversationsIfNeeded(
        _ pairs: [(providerID: String, modelID: String)]
    ) {
        guard !defaults.bool(forKey: modelUsageSeededKey) else { return }
        defaults.set(true, forKey: modelUsageSeededKey)
        guard !pairs.isEmpty else {
            persistModelUsageCounts()
            return
        }

        var tallies: [String: Int] = [:]
        for pair in pairs {
            let key = Self.modelUsageKey(providerID: pair.providerID, modelID: pair.modelID)
            tallies[key, default: 0] += 1
        }
        for (key, tally) in tallies {
            modelUsageCounts[key] = max(modelUsageCounts[key] ?? 0, tally)
        }
        persistModelUsageCounts()
    }

    /// Most-used first; preserves original relative order for ties.
    static func sortedByUsage<T>(
        _ items: [T],
        usageCount: (T) -> Int
    ) -> [T] {
        items.enumerated()
            .sorted { lhs, rhs in
                let leftCount = usageCount(lhs.element)
                let rightCount = usageCount(rhs.element)
                if leftCount != rightCount {
                    return leftCount > rightCount
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Picker order: current selection first, then starred (when not filtering), then usage.
    static func sortedForModelPicker<T>(
        _ items: [T],
        isFiltering: Bool,
        isCurrent: (T) -> Bool,
        isStarred: (T) -> Bool,
        usageCount: (T) -> Int
    ) -> [T] {
        let ranked = sortedByUsage(items, usageCount: usageCount)
        var current: [T] = []
        var rest: [T] = []
        current.reserveCapacity(1)
        rest.reserveCapacity(ranked.count)
        for item in ranked {
            if isCurrent(item) {
                current.append(item)
            } else {
                rest.append(item)
            }
        }
        guard !isFiltering else { return current + rest }

        var starred: [T] = []
        var unstarred: [T] = []
        starred.reserveCapacity(rest.count)
        unstarred.reserveCapacity(rest.count)
        for item in rest {
            if isStarred(item) {
                starred.append(item)
            } else {
                unstarred.append(item)
            }
        }
        return current + starred + unstarred
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

    private func loadModelUsageCounts() {
        guard let stored = defaults.dictionary(forKey: modelUsageCountsKey) as? [String: Int] else {
            modelUsageCounts = [:]
            return
        }
        modelUsageCounts = stored
    }

    private func persistModelUsageCounts() {
        defaults.set(modelUsageCounts, forKey: modelUsageCountsKey)
    }

    private func loadLastSelectedModel() {
        lastSelectedModelUsageKey = defaults.string(forKey: lastSelectedModelKey)
    }

    private func loadStarredModels() {
        guard let stored = defaults.array(forKey: starredModelsKey) as? [String] else {
            starredModelKeys = []
            return
        }
        starredModelKeys = Set(stored)
    }

    private func persistStarredModels() {
        defaults.set(Array(starredModelKeys).sorted(), forKey: starredModelsKey)
    }
}

import Foundation
import Observation

/// Owns the list of providers the user has configured and their API keys.
/// Non-secret provider metadata is persisted as JSON in `UserDefaults`;
/// API keys live in the Keychain via `KeychainStore`.
@Observable
final class ProviderStore {
    private(set) var providers: [ConfiguredProvider] = []
    private let defaultsKey = "com.openchat.configuredProviders"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
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
        provider(withID: providerID)?.models.first { $0.id == modelID }
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
}

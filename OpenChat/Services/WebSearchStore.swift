import Foundation
import Observation

/// Owns BYOK keys for search providers, which provider is active, and the
/// global search enable switch. The active provider is chosen from chat.
@MainActor
@Observable
final class WebSearchStore {
    private let enabledDefaultsKey = "com.openchat.webSearch.enabled"
    private let activeProviderDefaultsKey = "com.openchat.webSearch.activeProvider"
    private let defaults: UserDefaults
    /// Bumped when Keychain-backed credentials change so Observation can refresh views.
    private var credentialsEpoch = 0

    private(set) var isEnabled: Bool
    private(set) var activeProvider: WebSearchProviderKind

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: enabledDefaultsKey) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = defaults.bool(forKey: enabledDefaultsKey)
        }

        if let raw = defaults.string(forKey: activeProviderDefaultsKey),
           let kind = WebSearchProviderKind(rawValue: raw) {
            self.activeProvider = kind
        } else {
            self.activeProvider = .tavily
        }

        migrateLegacyTavilyKeyIfNeeded()
        if apiKey(for: activeProvider) == nil,
           let firstConfigured = WebSearchProviderKind.allCases.first(where: { apiKey(for: $0) != nil }) {
            activeProvider = firstConfigured
            defaults.set(firstConfigured.rawValue, forKey: activeProviderDefaultsKey)
        }
    }

    /// True when any search provider has a key.
    var hasAnyAPIKey: Bool {
        WebSearchProviderKind.allCases.contains { apiKey(for: $0) != nil }
    }

    /// Providers that currently have a stored key.
    var configuredProviders: [WebSearchProviderKind] {
        _ = credentialsEpoch
        return WebSearchProviderKind.allCases.filter { apiKey(for: $0) != nil }
    }

    /// Global search is on and the active provider has a usable key.
    var isActive: Bool {
        isEnabled && apiKey(for: activeProvider) != nil
    }

    var activeProviderDisplayName: String {
        activeProvider.displayName
    }

    func hasAPIKey(for kind: WebSearchProviderKind) -> Bool {
        apiKey(for: kind) != nil
    }

    func apiKey(for kind: WebSearchProviderKind) -> String? {
        _ = credentialsEpoch
        if let key = KeychainStore.get(kind.keychainAccount), !key.isEmpty {
            return key
        }
        if let legacy = kind.legacyKeychainAccount,
           let key = KeychainStore.get(legacy), !key.isEmpty {
            return key
        }
        return nil
    }

    func redactedAPIKey(for kind: WebSearchProviderKind) -> String? {
        guard let key = apiKey(for: kind) else { return nil }
        return APIKeyRedaction.redacted(key)
    }

    /// Active provider key, if configured.
    func activeAPIKey() -> String? {
        apiKey(for: activeProvider)
    }

    func setAPIKey(_ apiKey: String, for kind: WebSearchProviderKind) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.set(trimmed, forKey: kind.keychainAccount)
        if let legacy = kind.legacyKeychainAccount {
            KeychainStore.remove(legacy)
        }
        credentialsEpoch &+= 1

        if !isEnabled || activeAPIKey() == nil {
            setActiveProvider(kind)
            setEnabled(true)
        }
    }

    func removeAPIKey(for kind: WebSearchProviderKind) {
        KeychainStore.remove(kind.keychainAccount)
        if let legacy = kind.legacyKeychainAccount {
            KeychainStore.remove(legacy)
        }
        credentialsEpoch &+= 1

        if activeProvider == kind {
            if let next = configuredProviders.first {
                setActiveProvider(next)
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: enabledDefaultsKey)
    }

    func setActiveProvider(_ kind: WebSearchProviderKind) {
        activeProvider = kind
        defaults.set(kind.rawValue, forKey: activeProviderDefaultsKey)
    }

    func makeActiveClient() -> (any WebSearchClient)? {
        guard activeAPIKey() != nil else { return nil }
        return WebSearchClientFactory.client(for: activeProvider)
    }

    private func migrateLegacyTavilyKeyIfNeeded() {
        let kind = WebSearchProviderKind.tavily
        guard KeychainStore.get(kind.keychainAccount) == nil,
              let legacy = kind.legacyKeychainAccount,
              let key = KeychainStore.get(legacy), !key.isEmpty
        else { return }
        KeychainStore.set(key, forKey: kind.keychainAccount)
        KeychainStore.remove(legacy)
        credentialsEpoch &+= 1
    }
}

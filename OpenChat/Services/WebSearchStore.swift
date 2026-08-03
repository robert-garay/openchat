import Foundation
import Observation

/// Owns the optional Tavily API key and whether web search is enabled.
/// The key lives in the Keychain; the enabled flag is in UserDefaults.
@MainActor
@Observable
final class WebSearchStore {
    private let keychainAccount = "tavily"
    private let enabledDefaultsKey = "com.openchat.webSearch.enabled"
    private let defaults: UserDefaults
    /// Bumped when Keychain-backed credentials change so Observation can refresh views.
    private var credentialsEpoch = 0

    private(set) var isEnabled: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: enabledDefaultsKey) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = defaults.bool(forKey: enabledDefaultsKey)
        }
    }

    /// True when a non-empty Tavily key is stored.
    var hasAPIKey: Bool {
        apiKey() != nil
    }

    /// Search runs only when the user has a key and has left the feature on.
    var isActive: Bool {
        isEnabled && hasAPIKey
    }

    func apiKey() -> String? {
        _ = credentialsEpoch
        let key = KeychainStore.get(keychainAccount)
        return (key?.isEmpty ?? true) ? nil : key
    }

    func redactedAPIKey() -> String? {
        guard let key = apiKey() else { return nil }
        return APIKeyRedaction.redacted(key)
    }

    func setAPIKey(_ apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.set(trimmed, forKey: keychainAccount)
        credentialsEpoch &+= 1
        // Adding a key implies the user wants search on.
        setEnabled(true)
    }

    func removeAPIKey() {
        KeychainStore.remove(keychainAccount)
        credentialsEpoch &+= 1
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: enabledDefaultsKey)
    }
}

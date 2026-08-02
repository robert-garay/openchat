import Foundation

/// Build-time secrets injected via Info.plist / Xcode build settings.
/// Set `OPENCHAT_MANAGED_OPENROUTER_API_KEY` to a spend-limited OpenRouter key
/// dedicated to included Qwen3.7 Flash access (never reuse a personal unlimited key).
enum AppSecrets {
    private static let managedOpenRouterInfoKey = "OPENCHAT_MANAGED_OPENROUTER_API_KEY"

    /// Spend-controlled OpenRouter key used only for `ManagedFreeTier`.
    static var managedOpenRouterAPIKey: String? {
        resolvedManagedOpenRouterAPIKey(from: Bundle.main)
    }

    static func resolvedManagedOpenRouterAPIKey(from bundle: Bundle) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: managedOpenRouterInfoKey) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Unsubstituted build setting placeholder — treat as unset.
        if trimmed.hasPrefix("$(") { return nil }
        return trimmed
    }
}

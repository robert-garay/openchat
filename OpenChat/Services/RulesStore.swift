import Foundation
import Observation

/// Persists global behavior-steering rules on-device (UserDefaults).
@MainActor
@Observable
final class RulesStore {
    static let globalRulesDefaultsKey = "com.openchat.rules.global"

    private let defaults: UserDefaults

    var globalRules: String {
        get { defaults.string(forKey: Self.globalRulesDefaultsKey) ?? "" }
        set { defaults.set(newValue, forKey: Self.globalRulesDefaultsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}

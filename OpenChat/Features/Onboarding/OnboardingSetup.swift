import Foundation

enum OnboardingSetup {
    static let completedKey = "com.openchat.setupOnboardingCompleted"
    static let skippedLocalKey = "com.openchat.setupSkippedLocalDownload"

    /// Bump when the on-device setup experience changes so update users see it once.
    static let localModelsSetupExperienceVersionKey = "com.openchat.localModelsSetupExperienceVersion"
    static let localModelsSetupExperienceVersion = 1

    static func shouldPresentSetup(setupCompleted: Bool) -> Bool {
        if !setupCompleted { return true }
        let seenVersion = UserDefaults.standard.integer(forKey: localModelsSetupExperienceVersionKey)
        return seenVersion < localModelsSetupExperienceVersion
    }

    static func markLocalModelsSetupExperienceSeen() {
        UserDefaults.standard.set(
            localModelsSetupExperienceVersion,
            forKey: localModelsSetupExperienceVersionKey
        )
    }
}

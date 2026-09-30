import SwiftUI

/// First-run and one-time post-update on-device setup on a single scrollable page.
struct FirstLaunchOnboardingView: View {
    @Environment(ProviderStore.self) private var providerStore
    @Environment(LocalModelStore.self) private var localModelStore

    @AppStorage(OnboardingSetup.completedKey) private var setupCompleted = false

    var body: some View {
        NavigationStack {
            LocalModelsOnboardingView(flow: .firstLaunch) {
                finishSetup()
            }
        }
    }

    private func finishSetup() {
        OnboardingSetup.markLocalModelsSetupExperienceSeen()
        setupCompleted = true
    }
}

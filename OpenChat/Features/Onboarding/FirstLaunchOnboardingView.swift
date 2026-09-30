import SwiftUI

/// First-run and one-time post-update setup: local models, then the existing provider welcome.
struct FirstLaunchOnboardingView: View {
    @Environment(ProviderStore.self) private var providerStore
    @AppStorage(OnboardingSetup.completedKey) private var setupCompleted = false
    @State private var phase: Phase = .localModels

    private enum Phase {
        case localModels
        case cloudProviders
    }

    var body: some View {
        Group {
            switch phase {
            case .localModels:
                NavigationStack {
                    LocalModelsOnboardingView(flow: .firstLaunch) {
                        advanceToCloudProviders()
                    }
                }
            case .cloudProviders:
                WelcomeView(showsOnDeviceEntry: false, onSkipOrContinueWithLocal: finishSetup)
                    .onChange(of: providerStore.enabledProviders.map(\.id)) { _, ids in
                        let hasCloud = ids.contains { $0 != OnDeviceProvider.providerID }
                        if hasCloud {
                            finishSetup()
                        }
                    }
            }
        }
    }

    private func advanceToCloudProviders() {
        OnboardingSetup.markLocalModelsSetupExperienceSeen()
        phase = .cloudProviders
    }

    private func finishSetup() {
        OnboardingSetup.markLocalModelsSetupExperienceSeen()
        setupCompleted = true
    }
}

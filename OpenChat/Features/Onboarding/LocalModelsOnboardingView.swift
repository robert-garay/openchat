import SwiftUI

enum LocalModelsOnboardingFlow {
    case settingsSheet
    case firstLaunch
}

struct LocalModelsOnboardingView: View {
    var flow: LocalModelsOnboardingFlow = .settingsSheet
    var onFirstLaunchContinue: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(LocalModelStore.self) private var localModelStore
    @Environment(ProviderStore.self) private var providerStore

    @State private var expandedVendorID: String?

    init(
        flow: LocalModelsOnboardingFlow = .settingsSheet,
        onFirstLaunchContinue: (() -> Void)? = nil
    ) {
        self.flow = flow
        self.onFirstLaunchContinue = onFirstLaunchContinue
    }

    private var vendorGroups: [(vendor: LocalModelVendor, models: [LocalModelManifestEntry])] {
        LocalModelVendor.groupedDownloadableEntries(from: localModelStore.compatibleDownloadableEntries())
    }

    private var recommendedModelIDs: Set<String> {
        Set(localModelStore.recommendationResult(preference: localModelStore.intelligencePreference)?.picks.map(\.entry.id) ?? [])
    }

    private var deviceContext: DeviceContext {
        localModelStore.deviceContext().withPreference(localModelStore.intelligencePreference)
    }

    var body: some View {
        List {
            introSection
            deviceSection
            providerSections
            wifiSection
            if flow == .firstLaunch {
                firstLaunchCloudSection
                firstLaunchFinishSection
            } else {
                settingsFinishSection
            }
        }
        .listSectionSpacing(8)
        .navigationTitle(flow == .firstLaunch ? "Chat on your iPhone" : "On-Device Models")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if flow == .settingsSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { skipFirstLaunch() }
                }
            }
        }
    }

    private var introSection: some View {
        Section {
            Text("Download a private model that runs on your iPhone. Pick a provider, choose a model, and tap Download. You can fetch more than one model at a time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var deviceSection: some View {
        Section {
            LocalModelDevicePropertiesDisclosure(context: deviceContext)
        }
    }

    @ViewBuilder
    private var providerSections: some View {
        Section {
            ForEach(vendorGroups, id: \.vendor.id) { group in
                LocalModelProviderSection(
                    vendor: group.vendor,
                    models: group.models,
                    recommendedModelIDs: recommendedModelIDs,
                    expandedVendorID: $expandedVendorID
                )
            }
        }
    }

    private var wifiSection: some View {
        Section {
            Toggle("Download on Wi‑Fi only", isOn: Binding(
                get: { localModelStore.wifiOnlyDownloads },
                set: { localModelStore.wifiOnlyDownloads = $0 }
            ))
        } footer: {
            Text("Downloads are verified against the OpenChat catalog (SHA-256).")
        }
    }

    private var firstLaunchCloudSection: some View {
        Section {
            if hasLocalModel {
                Label("On-device model ready — no API key needed to start chatting.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                Text("Optional: add an API key for OpenAI, Claude, Gemini, OpenRouter, or a custom endpoint.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            NavigationLink {
                AddProviderView(dismissesOnSave: false)
            } label: {
                Label("Add a cloud provider", systemImage: "key.fill")
            }
            if hasCloudProvider {
                Label("Provider connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Cloud providers")
        }
    }

    private var firstLaunchFinishSection: some View {
        Section {
            Button {
                completeFirstLaunch()
            } label: {
                Text(finishButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .disabled(!canFinishFirstLaunch)
        } footer: {
            if !canFinishFirstLaunch {
                Text("Install an on-device model or connect a cloud provider to continue.")
            }
        }
    }

    private var settingsFinishSection: some View {
        Section {
            if hasLocalModel {
                Button("Done") { dismiss() }
                    .font(.headline)
            }
        }
    }

e var canFinishFirstLaunch: Bool {
        hasLocalModel || hasCloudProvider
    }

    private var finishButtonTitle: String {
        hasLocalModel ? "Get started" : "Get started with cloud"
    }

    private func skipFirstLaunch() {
        UserDefaults.standard.set(true, forKey: OnboardingSetup.skippedLocalKey)
        if canFinishFirstLaunch {
            completeFirstLaunch()
        }
    }

    private func completeFirstLaunch() {
        guard canFinishFirstLaunch else { return }
        UserDefaults.standard.set(!hasLocalModel, forKey: OnboardingSetup.skippedLocalKey)
        OnboardingSetup.markLocalModelsSetupExperienceSeen()
        Haptics.light()
        onFirstLaunchContinue?()
    }
}

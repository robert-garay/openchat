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
    @State private var selectedPreference: IntelligencePreference = .everydayChat

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
        Set(localModelStore.recommendationResult(preference: selectedPreference)?.picks.map(\.entry.id) ?? [])
    }

    private var deviceContext: DeviceContext {
        localModelStore.deviceContext().withPreference(selectedPreference)
    }

    var body: some View {
        List {
            introSection
            deviceSection
            preferenceSection
            providerSections
            wifiSection
            if flow == .firstLaunch {
                firstLaunchCloudSection
                firstLaunchFinishSection
            } else {
                settingsFinishSection
            }
        }
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
        .onAppear {
            selectedPreference = localModelStore.intelligencePreference
            if expandedVendorID == nil {
                expandedVendorID = vendorGroups.first?.vendor.id
            }
        }
        .onChange(of: selectedPreference) { _, value in
            localModelStore.intelligencePreference = value
        }
    }

    private var introSection: some View {
        Section {
            Text("Download a private model that runs on your iPhone—no API key required. Pick a provider, choose a model, and tap Download. You can fetch more than one model at a time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var deviceSection: some View {
        Section {
            if let result = localModelStore.recommendationResult(preference: selectedPreference) {
                Text(result.deviceSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LocalModelDevicePropertiesDisclosure(context: deviceContext)
        }
    }

    private var preferenceSection: some View {
        Section {
            Picker("Recommendation style", selection: $selectedPreference) {
                ForEach(availablePreferences, id: \.self) { preference in
                    Text(preference.title).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            Text(selectedPreference.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Tier focus")
        } footer: {
            Text("Fast, Balanced, and Strongest labels on each model reflect catalog size; suggestions follow your iPhone and this focus.")
        }
    }

    @ViewBuilder
    private var providerSections: some View {
        ForEach(vendorGroups, id: \.vendor.id) { group in
            LocalModelProviderSection(
                vendor: group.vendor,
                models: group.models,
                recommendedModelIDs: recommendedModelIDs,
                expandedVendorID: $expandedVendorID
            )
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

    private var availablePreferences: [IntelligencePreference] {
        IntelligencePreference.allCases.filter { preference in
            preference != .bestOnDevice || localModelStore.deviceTier >= .standard6GB
        }
    }

    private var hasLocalModel: Bool {
        !localModelStore.readyEntries.isEmpty
    }

    private var hasCloudProvider: Bool {
        providerStore.providers.contains { $0.id != OnDeviceProvider.providerID }
    }

    private var canFinishFirstLaunch: Bool {
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

import SwiftUI

enum LocalModelsOnboardingFlow {
    /// Presented in a sheet (e.g. Welcome) with Close / Done.
    case settingsSheet
    /// Pushed from Settings — same content, standard navigation back.
    case settings
    case firstLaunch
}

struct LocalModelsOnboardingView: View {
    var flow: LocalModelsOnboardingFlow = .settingsSheet
    var onFirstLaunchContinue: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(LocalModelStore.self) private var localModelStore
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

    private var deviceContext: DeviceContext {
        localModelStore.deviceContext().withPreference(localModelStore.intelligencePreference)
    }

    private var hasLocalModel: Bool {
        !localModelStore.readyEntries.isEmpty
    }

    var body: some View {
        List {
            introSection
            deviceSection
            providerSections
            wifiSection
            if flow == .firstLaunch {
                firstLaunchFinishSection
            } else if flow == .settingsSheet {
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
            } else if flow == .firstLaunch {
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

    private var firstLaunchFinishSection: some View {
        Section {
            Button {
                completeFirstLaunch(skippedLocal: !hasLocalModel)
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .disabled(!hasLocalModel)
        } footer: {
            if !hasLocalModel {
                Text("Download a model, or tap Skip to set up a cloud provider next.")
            } else {
                Text("Next: connect a cloud provider if you want — optional when a local model is ready.")
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

    private func skipFirstLaunch() {
        completeFirstLaunch(skippedLocal: true)
    }

    private func completeFirstLaunch(skippedLocal: Bool) {
        UserDefaults.standard.set(skippedLocal, forKey: OnboardingSetup.skippedLocalKey)
        OnboardingSetup.markLocalModelsSetupExperienceSeen()
        Haptics.light()
        onFirstLaunchContinue?()
    }
}

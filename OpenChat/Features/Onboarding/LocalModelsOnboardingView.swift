import SwiftUI

enum LocalModelsOnboardingFlow {
    case settingsSheet
    case firstLaunch
}

struct LocalModelsOnboardingView: View {
    var flow: LocalModelsOnboardingFlow = .settingsSheet
    var onFirstLaunchAdvance: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(LocalModelStore.self) private var localModelStore
    @Environment(ProviderStore.self) private var providerStore

    @State private var step = 0
    @State private var selectedPreference: IntelligencePreference = .everydayChat
    @State private var selectedEntryID: String?
    @State private var showAllModels = false

    init(
        flow: LocalModelsOnboardingFlow = .settingsSheet,
        onFirstLaunchAdvance: (() -> Void)? = nil
    ) {
        self.flow = flow
        self.onFirstLaunchAdvance = onFirstLaunchAdvance
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0:
                    privacyStep
                case 1:
                    intelligenceStep
                default:
                    downloadStep
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
                        Button("Skip") { skipLocalAndAdvance() }
                    }
                }
            }
        }
        .onAppear {
            selectedPreference = localModelStore.intelligencePreference
            if let primary = localModelStore.recommendedPrimaryEntry() {
                selectedEntryID = primary.id
            }
        }
    }

    private var privacyStep: some View {
        List {
            Section {
                Text("Download a private model that runs on your iPhone—no API key required. Or skip and use cloud providers instead.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Good to know") {
                Label("Downloads are about 0.3–4 GB depending on the model.", systemImage: "externaldrive")
                Label("6 GB RAM or more works best for balanced models.", systemImage: "memorychip")
                Label("Wi‑Fi only is on by default.", systemImage: "wifi")
                Label("Great for private drafts—not a replacement for large cloud models.", systemImage: "exclamationmark.circle")
            }
            Section {
                Button("Choose a model") { step = 1 }
                    .font(.headline)
                if flow == .firstLaunch {
                    Button("Skip — use cloud instead") { skipLocalAndAdvance() }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var intelligenceStep: some View {
        List {
            Section {
                Text("Picks for your iPhone (\(localModelStore.deviceTier.displayLabel)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("What matters most?") {
                ForEach(IntelligencePreference.allCases, id: \.self) { preference in
                    if preference != .bestOnDevice || localModelStore.deviceTier >= .standard6GB {
                        Button {
                            selectedPreference = preference
                            localModelStore.intelligencePreference = preference
                            if let primary = primaryEntry(for: preference) {
                                selectedEntryID = primary.id
                            }
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preference.title)
                                        .font(.body.weight(.semibold))
                                    Text(preference.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedPreference == preference {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section {
                Button("See recommendations") { step = 2 }
                    .font(.headline)
            }
        }
    }

    private var downloadStep: some View {
        List {
            if let result = localModelStore.recommendationResult() {
                LocalModelRecommendationSection(
                    result: result,
                    selectedEntryID: $selectedEntryID
                )
            } else if let entry = selectedEntry {
                Section("Recommended") {
                    modelRow(entry)
                }
            }

            if showAllModels {
                Section("All compatible downloads") {
                    ForEach(localModelStore.compatibleDownloadableEntries()) { entry in
                        if entry.id != selectedEntry?.id {
                            modelRow(entry)
                        }
                    }
                }
            } else if localModelStore.compatibleDownloadableEntries().count > 1 {
                Section {
                    Button("See all compatible models") { showAllModels = true }
                }
            }

            Section {
                Toggle("Download on Wi‑Fi only", isOn: Binding(
                    get: { localModelStore.wifiOnlyDownloads },
                    set: { localModelStore.wifiOnlyDownloads = $0 }
                ))
            }

            if let progress = localModelStore.downloadProgress {
                Section("Downloading") {
                    ProgressView(value: progress.fractionCompleted)
                    Text("\(Int(progress.fractionCompleted * 100))% · \(formattedBytes(progress.receivedBytes)) of \(formattedBytes(progress.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if let entry = selectedEntry {
                    let state = localModelStore.record(for: entry.id).state
                    switch state {
                    case .ready:
                        Button(finishAfterDownloadTitle) { completeLocalPath() }
                            .font(.headline)
                    case .downloading:
                        Button("Cancel download", role: .destructive) {
                            localModelStore.cancelDownload()
                        }
                    default:
                        if let block = downloadBlockReason(for: entry) {
                            Text(block)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Button("Download \(friendlyName(for: entry))") {
                            localModelStore.startDownload(entry: entry, providerStore: providerStore)
                        }
                        .font(.headline)
                        .disabled(downloadDisabled(for: entry))
                    }
                }
            } footer: {
                if let error = localModelStore.record(for: selectedEntry?.id ?? "").lastError {
                    Text(error)
                } else {
                    Text("Downloads are verified against the OpenChat catalog (SHA-256).")
                }
            }
        }
    }

    private var finishAfterDownloadTitle: String {
        flow == .firstLaunch ? "Continue" : "Start chatting"
    }

    private func skipLocalAndAdvance() {
        UserDefaults.standard.set(true, forKey: OnboardingSetup.skippedLocalKey)
        if flow == .firstLaunch {
            onFirstLaunchAdvance?()
        } else {
            dismiss()
        }
    }

    private func completeLocalPath() {
        UserDefaults.standard.set(false, forKey: OnboardingSetup.skippedLocalKey)
        if flow == .firstLaunch {
            onFirstLaunchAdvance?()
        } else {
            dismiss()
        }
    }

    private var selectedEntry: LocalModelManifestEntry? {
        if let id = selectedEntryID,
           let entry = localModelStore.manifest?.models.first(where: { $0.id == id }) {
            return entry
        }
        return localModelStore.recommendedPrimaryEntry()
    }

    private func primaryEntry(for preference: IntelligencePreference) -> LocalModelManifestEntry? {
        localModelStore.recommendationResult(preference: preference)?.primary?.entry
            ?? localModelStore.recommendationResult(preference: preference)?
            .picks.first(where: { !$0.isBlockedForDownload })?.entry
    }

    private func downloadDisabled(for entry: LocalModelManifestEntry) -> Bool {
        downloadBlockReason(for: entry) != nil
    }

    private func downloadBlockReason(for entry: LocalModelManifestEntry) -> String? {
        if entry.minRAMGB > localModelStore.deviceTier.minRAMGB {
            return String(localized: "This model needs about \(entry.minRAMGB) GB of device memory.")
        }
        if let pick = localModelStore.recommendationResult()?.picks.first(where: { $0.entry.id == entry.id }),
           pick.isBlockedForDownload {
            return pick.blockReason
        }
        return nil
    }

    private func friendlyName(for entry: LocalModelManifestEntry) -> String {
        if let pick = localModelStore.recommendationResult()?.picks.first(where: { $0.entry.id == entry.id }) {
            return pick.pickLabel.title
        }
        return entry.displayName
    }

    @ViewBuilder
    private func modelRow(_ entry: LocalModelManifestEntry) -> some View {
        Button {
            selectedEntryID = entry.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                    Text(formattedBytes(entry.bytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedEntryID == entry.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func formattedBytes(_ bytes: Int) -> String {
        String(format: "%.1f GB download", Double(bytes) / 1_073_741_824.0)
    }
}

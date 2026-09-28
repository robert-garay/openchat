import SwiftUI

struct LocalModelsOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalModelStore.self) private var localModelStore
    @Environment(ProviderStore.self) private var providerStore

    @State private var step = 0
    @State private var selectedPreference: IntelligencePreference = .everydayChat
    @State private var selectedEntryID: String?
    @State private var showAllModels = false

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
            .navigationTitle("On-Device Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
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
                Text("After download, chat runs entirely on your iPhone. No API key and no inference traffic to OpenChat.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Before you download") {
                Label("Models use 1–4 GB of storage; keep free space for updates.", systemImage: "externaldrive")
                Label("Apple Silicon with 6 GB RAM or more is recommended for the default model.", systemImage: "memorychip")
                Label("Downloads use your network; Wi‑Fi is on by default.", systemImage: "wifi")
                Label("Phone-sized models are great for private drafts—not a GPT‑4 replacement.", systemImage: "exclamationmark.circle")
            }
            Section {
                Button("Continue") {
                    step = 1
                }
                .font(.headline)
            }
        }
    }

    private var intelligenceStep: some View {
        List {
            Section {
                Text("Optimized for your iPhone (\(localModelStore.deviceTier.displayLabel)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Intelligence") {
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
                Button("Continue") { step = 2 }
                    .font(.headline)
            }
        }
    }

    private var downloadStep: some View {
        List {
            if let entry = selectedEntry {
                Section("Recommended") {
                    modelRow(entry)
                }
            }

            if showAllModels {
                Section("Compatible models") {
                    ForEach(localModelStore.compatibleDownloadableEntries()) { entry in
                        if entry.id != selectedEntry?.id {
                            modelRow(entry)
                        }
                    }
                }
            } else {
                Section {
                    Button("See other compatible models") { showAllModels = true }
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
                        Button("Start chatting") { dismiss() }
                            .font(.headline)
                    case .downloading:
                        Button("Cancel download", role: .destructive) {
                            localModelStore.cancelDownload()
                        }
                    default:
                        Button("Download \(entry.displayName)") {
                            localModelStore.startDownload(entry: entry, providerStore: providerStore)
                        }
                        .font(.headline)
                        .disabled(entry.minRAMGB > localModelStore.deviceTier.minRAMGB)
                    }
                }
            } footer: {
                if let error = localModelStore.record(for: selectedEntry?.id ?? "").lastError {
                    Text(error)
                } else {
                    Text("Verified by the OpenChat model catalog (SHA-256).")
                }
            }
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
        guard let manifest = localModelStore.manifest else { return nil }
        let modelID = LocalModelRecommendationEngine.primaryModelID(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            preference: preference
        )
        guard let modelID else { return nil }
        return LocalModelsManifestLoader.entry(mlxModelID: modelID, in: manifest)
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
        let gb = Double(bytes) / 1_073_741_824.0
        return String(format: "%.1f GB", gb)
    }
}

import SwiftUI

struct LocalModelsSettingsView: View {
    @Environment(LocalModelStore.self) private var localModelStore
    @Environment(ProviderStore.self) private var providerStore
    @State private var showingOnboarding = false

    var body: some View {
        List {
            if let error = localModelStore.loadError {
                Section {
                    Text(error)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Optimized for \(localModelStore.deviceTier.displayLabel). On-device models keep chat private after download; they are not a substitute for large cloud models.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Installed") {
                let ready = localModelStore.readyEntries
                if ready.isEmpty {
                    Text("No models installed yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ready) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName)
                                if let bytes = localModelStore.record(for: entry.id).bytesOnDisk {
                                    Text(storageLabel(bytes))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Delete", role: .destructive) {
                                localModelStore.deleteModel(modelID: entry.id, providerStore: providerStore)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    showingOnboarding = true
                } label: {
                    Label(readyIsEmpty ? "Download a model" : "Add another model", systemImage: "arrow.down.circle")
                }
                Toggle("Wi‑Fi only downloads", isOn: Binding(
                    get: { localModelStore.wifiOnlyDownloads },
                    set: { localModelStore.wifiOnlyDownloads = $0 }
                ))
            }

            if let manifest = localModelStore.manifest {
                Section {
                    LabeledContent("Catalog version", value: "\(manifest.version)")
                }
            }
        }
        .navigationTitle("On-Device Models")
        .sheet(isPresented: $showingOnboarding) {
            LocalModelsOnboardingView()
        }
    }

    private var readyIsEmpty: Bool {
        localModelStore.readyEntries.isEmpty
    }

    private func storageLabel(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        return String(format: "%.1f GB on disk", gb)
    }
}

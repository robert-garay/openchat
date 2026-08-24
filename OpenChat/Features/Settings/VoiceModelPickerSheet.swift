import SwiftUI

/// Live-fetched, provider-grouped model picker for voice mode — the same
/// shape as `ModelPickerSheet` (provider logo + model rows, loading/error
/// states), scoped down to OpenAI's Realtime-capable models since that's the
/// only provider voice mode supports today.
struct VoiceModelPickerSheet: View {
    let currentModelID: String
    let onSelect: (String) -> Void

    @Environment(VoiceModeStore.self) private var voiceModeStore
    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.dismiss) private var dismiss

    private var openAIProvider: ConfiguredProvider? {
        providerStore.provider(withID: "openai")
    }

    var body: some View {
        NavigationStack {
            List {
                if voiceModeStore.isLoadingRealtimeModels, voiceModeStore.realtimeModels.isEmpty {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading models…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let error = voiceModeStore.realtimeModelsError, voiceModeStore.realtimeModels.isEmpty {
                    Section {
                        Text(error)
                            .foregroundStyle(.secondary)
                        Button("Try Again") { refresh(force: true) }
                    }
                } else if voiceModeStore.realtimeModels.isEmpty {
                    Section {
                        Text("No Realtime API models available for this account.")
                            .foregroundStyle(.secondary)
                    }
                } else if let provider = openAIProvider {
                    Section(provider.name) {
                        ForEach(voiceModeStore.realtimeModels) { model in
                            modelRow(model, provider: provider)
                        }
                    }
                }
            }
            .navigationTitle("Voice Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { refresh(force: false) }
        }
    }

    private func modelRow(_ model: RealtimeModelInfo, provider: ConfiguredProvider) -> some View {
        Button {
            onSelect(model.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ProviderLogoView(
                    logoAssetName: provider.logoAssetName,
                    symbolName: provider.symbolName,
                    tint: Color(hex: provider.tint),
                    size: 28
                )
                Text(model.displayName)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                if model.id == currentModelID {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func refresh(force: Bool) {
        guard let provider = openAIProvider else { return }
        voiceModeStore.refreshRealtimeModelsIfNeeded(
            baseURL: provider.baseURL,
            apiKey: providerStore.apiKey(for: provider),
            force: force
        )
    }
}

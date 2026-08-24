import SwiftUI

struct VoiceModeSettingsView: View {
    @Environment(VoiceModeStore.self) private var voiceModeStore
    @Environment(ProviderStore.self) private var providerStore
    @State private var showingModelPicker = false

    private var hasOpenAIKey: Bool {
        guard let provider = providerStore.provider(withID: "openai") else { return false }
        return providerStore.apiKey(for: provider) != nil
    }

    private var selectedModelDisplayName: String {
        guard !voiceModeStore.modelID.isEmpty else { return "Choose a model" }
        if let match = voiceModeStore.realtimeModels.first(where: { $0.id == voiceModeStore.modelID }) {
            return match.displayName
        }
        return voiceModeStore.modelID
    }

    private var availableVoices: [RealtimeVoiceOption] {
        voiceModeStore.voices(for: voiceModeStore.modelID)
    }

    var body: some View {
        List {
            Section {
                Label {
                    Text(
                        "Talk instead of type, in any chat, regardless of that chat's own model. "
                        + "Voice mode always uses OpenAI's Realtime API — pick which model and voice below."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.accentColor)
                }
            }

            Section {
                Toggle("Enable Voice Mode", isOn: Binding(
                    get: { voiceModeStore.isEnabled },
                    set: { voiceModeStore.setEnabled($0) }
                ))
                .disabled(!hasOpenAIKey)
            } footer: {
                if !hasOpenAIKey {
                    Text("Add an OpenAI API key in Providers to use voice mode.")
                }
            }

            Section {
                Button {
                    showingModelPicker = true
                } label: {
                    HStack {
                        Text("Model")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(selectedModelDisplayName)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                Picker("Voice", selection: Binding(
                    get: { voiceModeStore.voice },
                    set: { voiceModeStore.setVoice($0) }
                )) {
                    ForEach(availableVoices) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } footer: {
                Text("The model list is fetched live from OpenAI. Changes apply the next time you start a voice mode call.")
            }
            .disabled(!voiceModeStore.isEnabled)
        }
        .navigationTitle("Voice Mode")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingModelPicker) {
            VoiceModelPickerSheet(currentModelID: voiceModeStore.modelID) { modelID in
                voiceModeStore.setModel(modelID)
            }
        }
    }
}

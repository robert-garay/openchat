import SwiftUI

struct VoiceModeSettingsView: View {
    @Environment(VoiceModeStore.self) private var voiceModeStore
    @Environment(ProviderStore.self) private var providerStore

    private var hasOpenAIKey: Bool {
        guard let provider = providerStore.provider(withID: "openai") else { return false }
        return providerStore.apiKey(for: provider) != nil
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
                Picker("Model", selection: Binding(
                    get: { voiceModeStore.model },
                    set: { voiceModeStore.setModel($0) }
                )) {
                    ForEach(RealtimeModelOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Picker("Voice", selection: Binding(
                    get: { voiceModeStore.voice },
                    set: { voiceModeStore.setVoice($0) }
                )) {
                    ForEach(RealtimeVoiceOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } footer: {
                Text("Applies the next time you start a voice mode call.")
            }
            .disabled(!voiceModeStore.isEnabled)
        }
        .navigationTitle("Voice Mode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

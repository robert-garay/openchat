import SwiftUI

struct VoiceModeSettingsView: View {
    @Environment(VoiceModeStore.self) private var voiceModeStore

    var body: some View {
        List {
            Section {
                Picker("Voice", selection: Binding(
                    get: { voiceModeStore.voice },
                    set: { voiceModeStore.setVoice($0) }
                )) {
                    ForEach(RealtimeVoiceOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } footer: {
                Text("The voice used when you start a voice mode call. Applies to your next call.")
            }
        }
        .navigationTitle("Voice Mode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

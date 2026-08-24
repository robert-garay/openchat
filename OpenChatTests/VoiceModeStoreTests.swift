import Testing
import Foundation
@testable import OpenChat

@MainActor
struct VoiceModeStoreTests {
    private static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.openchat.tests.voicemode.\(UUID().uuidString)")!
    }

    @Test("defaults to disabled, no model, alloy when nothing is stored")
    func defaultsAreUnset() {
        let store = VoiceModeStore(defaults: Self.makeDefaults())
        #expect(store.isEnabled == false)
        #expect(store.modelID.isEmpty)
        #expect(store.voice == .alloy)
    }

    @Test("setEnabled persists across store instances")
    func setEnabledPersists() {
        let defaults = Self.makeDefaults()
        let store = VoiceModeStore(defaults: defaults)

        store.setEnabled(true)
        #expect(store.isEnabled)

        let reloaded = VoiceModeStore(defaults: defaults)
        #expect(reloaded.isEnabled)
    }

    @Test("setModel persists across store instances")
    func setModelPersists() {
        let defaults = Self.makeDefaults()
        let store = VoiceModeStore(defaults: defaults)

        store.setModel("gpt-4o-mini-realtime-preview")
        #expect(store.modelID == "gpt-4o-mini-realtime-preview")

        let reloaded = VoiceModeStore(defaults: defaults)
        #expect(reloaded.modelID == "gpt-4o-mini-realtime-preview")
    }

    @Test("setVoice persists across store instances")
    func setVoicePersists() {
        let defaults = Self.makeDefaults()
        let store = VoiceModeStore(defaults: defaults)

        store.setVoice(.sage)
        #expect(store.voice == .sage)

        let reloaded = VoiceModeStore(defaults: defaults)
        #expect(reloaded.voice == .sage)
    }

    @Test("every RealtimeVoiceOption round-trips through raw value")
    func allVoiceOptionsRoundTrip() {
        for option in RealtimeVoiceOption.allCases {
            #expect(RealtimeVoiceOption(rawValue: option.rawValue) == option)
        }
    }

    @Test("voices(for:) returns the full voice list for any model id")
    func voicesForModelReturnsAllCases() {
        let store = VoiceModeStore(defaults: Self.makeDefaults())
        #expect(store.voices(for: "gpt-4o-realtime-preview") == RealtimeVoiceOption.allCases)
        #expect(store.voices(for: "some-future-model") == RealtimeVoiceOption.allCases)
    }
}

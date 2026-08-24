import Testing
import Foundation
@testable import OpenChat

@MainActor
struct VoiceModeStoreTests {
    private static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.openchat.tests.voicemode.\(UUID().uuidString)")!
    }

    @Test("defaults to disabled, gpt-4o-realtime-preview, alloy when nothing is stored")
    func defaultsAreUnset() {
        let store = VoiceModeStore(defaults: Self.makeDefaults())
        #expect(store.isEnabled == false)
        #expect(store.model == .gpt4oRealtimePreview)
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

        store.setModel(.gpt4oMiniRealtimePreview)
        #expect(store.model == .gpt4oMiniRealtimePreview)

        let reloaded = VoiceModeStore(defaults: defaults)
        #expect(reloaded.model == .gpt4oMiniRealtimePreview)
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

    @Test("every RealtimeModelOption round-trips through raw value")
    func allModelOptionsRoundTrip() {
        for option in RealtimeModelOption.allCases {
            #expect(RealtimeModelOption(rawValue: option.rawValue) == option)
        }
    }
}

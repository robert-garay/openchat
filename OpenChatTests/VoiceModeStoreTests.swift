import Testing
import Foundation
@testable import OpenChat

@MainActor
struct VoiceModeStoreTests {
    private static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.openchat.tests.voicemode.\(UUID().uuidString)")!
    }

    @Test("defaults to alloy when nothing is stored")
    func defaultsToAlloy() {
        let store = VoiceModeStore(defaults: Self.makeDefaults())
        #expect(store.voice == .alloy)
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
    func allOptionsRoundTrip() {
        for option in RealtimeVoiceOption.allCases {
            #expect(RealtimeVoiceOption(rawValue: option.rawValue) == option)
        }
    }
}

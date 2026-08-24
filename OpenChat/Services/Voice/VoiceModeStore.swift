import Foundation
import Observation

/// One of OpenAI's Realtime API voices.
enum RealtimeVoiceOption: String, CaseIterable, Identifiable, Sendable {
    case alloy
    case ash
    case ballad
    case coral
    case echo
    case sage
    case shimmer
    case verse

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

/// Persists the user's chosen voice-mode voice across calls.
@MainActor
@Observable
final class VoiceModeStore {
    private let voiceKey = "com.openchat.voiceMode.voice"

    @ObservationIgnored
    private let defaults: UserDefaults

    private(set) var voice: RealtimeVoiceOption

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: voiceKey), let stored = RealtimeVoiceOption(rawValue: raw) {
            voice = stored
        } else {
            voice = .alloy
        }
    }

    func setVoice(_ voice: RealtimeVoiceOption) {
        self.voice = voice
        defaults.set(voice.rawValue, forKey: voiceKey)
    }
}

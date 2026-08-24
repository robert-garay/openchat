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

/// A model exposed by OpenAI's Realtime API. Independent of any chat's own
/// selected provider/model — voice mode always talks to one of these.
enum RealtimeModelOption: String, CaseIterable, Identifiable, Sendable {
    case gpt4oRealtimePreview = "gpt-4o-realtime-preview"
    case gpt4oMiniRealtimePreview = "gpt-4o-mini-realtime-preview"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .gpt4oRealtimePreview: return "GPT-4o Realtime"
        case .gpt4oMiniRealtimePreview: return "GPT-4o Mini Realtime"
        }
    }
}

/// Persists voice mode's app-wide configuration: whether it's turned on, and
/// which Realtime API model/voice it uses. Independent of any chat's own
/// selected provider/model — mirrors how `WebSearchStore`/`SkillsStore` are
/// enabled once in Settings and then available everywhere.
@MainActor
@Observable
final class VoiceModeStore {
    private let enabledKey = "com.openchat.voiceMode.isEnabled"
    private let modelKey = "com.openchat.voiceMode.model"
    private let voiceKey = "com.openchat.voiceMode.voice"

    @ObservationIgnored
    private let defaults: UserDefaults

    private(set) var isEnabled: Bool
    private(set) var model: RealtimeModelOption
    private(set) var voice: RealtimeVoiceOption

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: enabledKey) == nil {
            isEnabled = false
        } else {
            isEnabled = defaults.bool(forKey: enabledKey)
        }
        if let raw = defaults.string(forKey: modelKey), let stored = RealtimeModelOption(rawValue: raw) {
            model = stored
        } else {
            model = .gpt4oRealtimePreview
        }
        if let raw = defaults.string(forKey: voiceKey), let stored = RealtimeVoiceOption(rawValue: raw) {
            voice = stored
        } else {
            voice = .alloy
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: enabledKey)
    }

    func setModel(_ model: RealtimeModelOption) {
        self.model = model
        defaults.set(model.rawValue, forKey: modelKey)
    }

    func setVoice(_ voice: RealtimeVoiceOption) {
        self.voice = voice
        defaults.set(voice.rawValue, forKey: voiceKey)
    }
}

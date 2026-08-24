import Foundation
import Observation

/// One of OpenAI's Realtime API voices. OpenAI has no endpoint that lists
/// available voices (unlike models), so this stays a hand-maintained list
/// matching their docs — see `VoiceModeStore.voices(for:)`.
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

/// Persists voice mode's app-wide configuration: whether it's turned on, and
/// which Realtime API model/voice it uses. Independent of any chat's own
/// selected provider/model — mirrors how `WebSearchStore`/`SkillsStore` are
/// enabled once in Settings and then available everywhere.
///
/// The model list is fetched live from OpenAI (`GET /models`, filtered for
/// realtime-capable models) rather than hardcoded, so new Realtime models
/// show up automatically. Voices have no such endpoint, so `voices(for:)`
/// returns a static list — scoped per model id so it's ready to diverge if a
/// future model ever supports a different subset.
@MainActor
@Observable
final class VoiceModeStore {
    private let enabledKey = "com.openchat.voiceMode.isEnabled"
    private let modelKey = "com.openchat.voiceMode.model"
    private let voiceKey = "com.openchat.voiceMode.voice"

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let modelsClient: ProviderModelsClient
    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?

    private(set) var isEnabled: Bool
    /// Raw OpenAI Realtime model id, e.g. "gpt-4o-realtime-preview". Empty
    /// until either restored from defaults or auto-picked from the first
    /// live-fetched result.
    private(set) var modelID: String
    private(set) var voice: RealtimeVoiceOption

    private(set) var realtimeModels: [RealtimeModelInfo] = []
    private(set) var isLoadingRealtimeModels = false
    private(set) var realtimeModelsError: String?
    private var hasFetchedRealtimeModels = false

    init(defaults: UserDefaults = .standard, modelsClient: ProviderModelsClient = ProviderModelsClient()) {
        self.defaults = defaults
        self.modelsClient = modelsClient
        if defaults.object(forKey: enabledKey) == nil {
            isEnabled = false
        } else {
            isEnabled = defaults.bool(forKey: enabledKey)
        }
        modelID = defaults.string(forKey: modelKey) ?? ""
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

    func setModel(_ modelID: String) {
        self.modelID = modelID
        defaults.set(modelID, forKey: modelKey)
    }

    func setVoice(_ voice: RealtimeVoiceOption) {
        self.voice = voice
        defaults.set(voice.rawValue, forKey: voiceKey)
    }

    /// Every model exposes the same documented voice set today, but this is
    /// scoped per model id rather than returning a flat constant, so a future
    /// model with a different voice lineup only needs a change here.
    func voices(for modelID: String) -> [RealtimeVoiceOption] {
        RealtimeVoiceOption.allCases
    }

    /// Fetches OpenAI's live model catalog, filtered for Realtime API models.
    /// Auto-selects the first result when nothing is stored yet.
    func refreshRealtimeModelsIfNeeded(baseURL: String, apiKey: String?, force: Bool = false) {
        guard !isLoadingRealtimeModels else { return }
        guard force || !hasFetchedRealtimeModels else { return }
        hasFetchedRealtimeModels = true

        refreshTask?.cancel()
        isLoadingRealtimeModels = true
        realtimeModelsError = nil
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let models = try await self.modelsClient.fetchRealtimeVoiceModels(baseURL: baseURL, apiKey: apiKey)
                guard !Task.isCancelled else { return }
                self.realtimeModels = models
                self.isLoadingRealtimeModels = false
                if self.modelID.isEmpty, let first = models.first {
                    self.setModel(first.id)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.realtimeModelsError = error.localizedDescription
                self.isLoadingRealtimeModels = false
            }
        }
    }
}

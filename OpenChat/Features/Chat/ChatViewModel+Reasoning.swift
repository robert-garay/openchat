import Foundation

extension ChatViewModel {
    var supportedEffortLevels: [EffortLevel] {
        currentModel?.supportedEffortLevels ?? []
    }

    var hasSeparateThinkingToggle: Bool {
        currentModel?.hasSeparateThinkingToggle ?? false
    }

    var isReasoningMandatory: Bool {
        currentModel?.isReasoningMandatory ?? false
    }

    /// The effort levels shown in the picker: the supported set with `none` removed when
    /// a separate thinking toggle handles on/off, or with `none` included when the same
    /// parameter controls both effort and off state.
    var pickerEffortLevels: [EffortLevel] {
        guard !supportedEffortLevels.isEmpty else { return [] }
        if hasSeparateThinkingToggle || isReasoningMandatory {
            return supportedEffortLevels.filter { $0 != .none }
        }
        return supportedEffortLevels
    }

    /// The effort level sent to the API, clamped to the model's supported set.
    var effectiveEffortLevel: EffortLevel {
        guard supportsEffort, !supportedEffortLevels.isEmpty else { return .default }
        if hasSeparateThinkingToggle, !isReasoningEnabled {
            // When a separate toggle exists and is off, the API should not receive an effort level.
            return supportedEffortLevels.first ?? .default
        }
        return supportedEffortLevels.contains(effortLevel) ? effortLevel : (supportedEffortLevels.last ?? .default)
    }

    /// Whether reasoning is effectively enabled for the next API request.
    var effectiveReasoningEnabled: Bool? {
        guard supportsEffort, hasSeparateThinkingToggle else { return nil }
        return isReasoningEnabled && !isReasoningMandatory
    }

}

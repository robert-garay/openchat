import Foundation

/// Discrete reasoning/thinking effort level. The exact set of supported values is
/// model-dependent (some models expose 3 levels, others 4, 5, 6, or 7), so the UI
/// adapts to the levels reported by the selected `AIModel`.
enum EffortLevel: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max

    var id: String { rawValue }

    /// Full ordered ladder (left to right / least to most reasoning).
    static var ordered: [EffortLevel] { [.none, .minimal, .low, .medium, .high, .xhigh, .max] }

    /// Display name matching the provider API terminology as closely as possible
    /// while keeping the label readable (e.g. "xhigh" becomes "xHigh").
    var displayName: String {
        switch self {
        case .none: "None"
        case .minimal: "Minimal"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "xHigh"
        case .max: "Max"
        }
    }

    var accessibilityLabel: String {
        "Effort: \(displayName)"
    }

    var index: Int {
        Self.ordered.firstIndex(of: self) ?? 3
    }

    init?(index: Int) {
        guard index >= 0, index < Self.ordered.count else { return nil }
        self = Self.ordered[index]
    }

    static var `default`: EffortLevel { .medium }

    /// Returns the supported effort levels for a model, inferred from its ID and name.
    /// Values are provider-specific and approximate; the source of truth is the API schema.
    static func inferred(for modelID: String, modelName: String) -> [EffortLevel] {
        let haystack = "\(modelID) \(modelName)".lowercased()

        // OpenAI GPT-5.6 family: all levels including off.
        if haystack.contains("gpt-5.6") {
            return [.none, .low, .medium, .high, .xhigh, .max]
        }

        // OpenAI GPT-5.5 / 5.4 / 5.2: off through xhigh.
        if haystack.contains("gpt-5.5") || haystack.contains("gpt-5.4") || haystack.contains("gpt-5.2") {
            return [.none, .low, .medium, .high, .xhigh]
        }

        // OpenAI GPT-5.1 / GPT-5 base: off through high.
        if haystack.contains("gpt-5.1") || (haystack.contains("gpt-5") && !haystack.contains("gpt-5.6")) {
            return [.none, .low, .medium, .high]
        }

        // OpenAI o3 / o4 series: low through xhigh.
        if haystack.contains("o3") || haystack.contains("o4") {
            return [.low, .medium, .high, .xhigh]
        }

        // OpenAI o1 series (except o1-mini): low through xhigh.
        if haystack.contains("o1") && !haystack.contains("o1-mini") {
            return [.low, .medium, .high, .xhigh]
        }

        // DeepSeek: high and max.
        if haystack.contains("deepseek") {
            return [.high, .max]
        }

        // Gemini 3.x: minimal through high.
        if haystack.contains("gemini-3") {
            return [.minimal, .low, .medium, .high]
        }

        // Gemini 2.5: low through high (no off).
        if haystack.contains("gemini-2.5") {
            return [.low, .medium, .high]
        }

        // Generic fallback for models that only advertise the capability.
        return [.low, .medium, .high]
    }
}

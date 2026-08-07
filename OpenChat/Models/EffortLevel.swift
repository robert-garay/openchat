import Foundation

/// Discrete effort level for models that expose a `reasoning_effort` / `effort`
/// parameter, mirroring the OpenAI API values. The UI renders this as a three-stop
/// slider with a gauge chip in the composer.
enum EffortLevel: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    /// Stable order shown in the lever (left to right).
    static var ordered: [EffortLevel] { [.low, .medium, .high] }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var accessibilityLabel: String {
        "Effort: \(displayName)"
    }

    var index: Int {
        Self.ordered.firstIndex(of: self) ?? 1
    }

    init?(index: Int) {
        guard index >= 0, index < Self.ordered.count else { return nil }
        self = Self.ordered[index]
    }

    static var `default`: EffortLevel { .medium }
}

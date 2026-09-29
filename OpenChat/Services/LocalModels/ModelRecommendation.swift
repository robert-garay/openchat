import Foundation

enum RecommendationPickLabel: String, Sendable, Equatable {
    case fast
    case balanced
    case strongest
    case alternative

    var title: String {
        switch self {
        case .fast:
            return String(localized: "Fast")
        case .balanced:
            return String(localized: "Balanced")
        case .strongest:
            return String(localized: "Strongest that fits")
        case .alternative:
            return String(localized: "Alternative")
        }
    }
}

struct RecommendationReason: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable {
        case ram
        case storage
        case chip
        case preference
        case downloadSize
        case warning
    }

    let kind: Kind
    let message: String

    var id: String { "\(kind.rawValue)-\(message)" }
}

struct RankedModelRecommendation: Sendable, Equatable, Identifiable {
    let entry: LocalModelManifestEntry
    let pickLabel: RecommendationPickLabel
    let isBlockedForDownload: Bool
    let blockReason: String?

    var id: String { entry.id }

    var mlxModelID: String { entry.mlxModelID }
}

struct ModelRecommendationResult: Sendable, Equatable {
    let picks: [RankedModelRecommendation]
    let reasons: [RecommendationReason]
    let deviceSummary: String

    var primary: RankedModelRecommendation? { picks.first }
}

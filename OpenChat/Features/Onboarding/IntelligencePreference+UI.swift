import Foundation

extension IntelligencePreference {
    var title: String {
        switch self {
        case .quickReplies:
            return String(localized: "Quick replies")
        case .everydayChat:
            return String(localized: "Everyday chat")
        case .bestOnDevice:
            return String(localized: "Best on your phone")
        }
    }

    var subtitle: String {
        switch self {
        case .quickReplies:
            return String(localized: "Fastest drafts and short answers. Lower quality than cloud models.")
        case .everydayChat:
            return String(localized: "Balanced daily chat on your device. Still not a cloud flagship.")
        case .bestOnDevice:
            return String(localized: "Largest model that fits your phone RAM. Slower and warmer.")
        }
    }
}

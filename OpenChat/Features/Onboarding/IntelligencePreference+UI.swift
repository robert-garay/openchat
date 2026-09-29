import Foundation

extension IntelligencePreference {
    var title: String {
        switch self {
        case .quickReplies:
            return String(localized: "Fast")
        case .everydayChat:
            return String(localized: "Balanced")
        case .bestOnDevice:
            return String(localized: "Strongest")
        }
    }

    var subtitle: String {
        switch self {
        case .quickReplies:
            return String(localized: "Smallest download, quickest replies. Best for short messages.")
        case .everydayChat:
            return String(localized: "Recommended mix of speed and quality for daily chat.")
        case .bestOnDevice:
            return String(localized: "Largest model that fits your RAM. Slower and uses more battery.")
        }
    }
}

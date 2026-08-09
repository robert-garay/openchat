import Foundation
import SwiftUI
import ActivityKit

/// Shared data shape for the OpenChat Live Activity. This file is included in both
/// the main app target and the Live Activity extension target.
struct OpenChatLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: Status
        var detail: String
    }

    enum Status: Codable, Hashable {
        case generating(elapsed: TimeInterval)
        case completed
        case failed
    }

    var conversationTitle: String
    var modelName: String
}

extension OpenChatLiveActivityAttributes.Status {
    var iconName: String {
        switch self {
        case .generating: "sparkles"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    var iconTint: Color {
        switch self {
        case .generating: .accentColor
        case .completed: .green
        case .failed: .red
        }
    }
}

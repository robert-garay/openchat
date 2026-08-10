import Foundation
import SwiftUI
import ActivityKit

/// Shared data shape for the OpenChat Live Activity. This file is included in both
/// the main app target and the Live Activity extension target.
struct OpenChatLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: Status
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
    var tintColor: Color {
        switch self {
        case .generating: .accentColor
        case .completed: .green
        case .failed: .red
        }
    }

    /// Only meaningful while `.generating`; other states report 0.
    var elapsed: TimeInterval {
        if case .generating(let elapsed) = self { elapsed }
        else { 0 }
    }

    var isGenerating: Bool {
        if case .generating = self { true } else { false }
    }
}

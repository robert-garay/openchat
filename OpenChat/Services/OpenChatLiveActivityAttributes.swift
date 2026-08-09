import Foundation
import ActivityKit

/// Shared data shape for the OpenChat Live Activity. This file is included in both
/// the main app target and the Live Activity extension target.
struct OpenChatLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: Status
        /// 0 = indeterminate, 1 = done. The UI treats 0 as a pulsing indeterminate bar.
        var progress: Int
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

import WidgetKit
import SwiftUI

@main
struct OpenChatLiveActivity: WidgetBundle {
    var body: some Widget {
        OpenChatLiveActivityWidget()
    }
}

struct OpenChatLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OpenChatLiveActivityAttributes.self) { context in
            OpenChatLiveActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            let status = context.state.status
            let isGenerating = if case .generating = status { true } else { false }
            let isFailed = if case .failed = status { true } else { false }

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    OpenChatLiveActivityExpandedLeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    OpenChatLiveActivityExpandedTrailing(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    OpenChatLiveActivityExpandedCenter(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    OpenChatLiveActivityExpandedBottom(context: context)
                }
            } compactLeading: {
                Image(systemName: isGenerating ? "sparkles" : "checkmark.circle.fill")
                    .foregroundStyle(isFailed ? .red : .accentColor)
            } compactTrailing: {
                Text(context.state.detail)
                    .font(.caption2)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: isGenerating ? "sparkles" : "checkmark.circle.fill")
                    .foregroundStyle(isFailed ? .red : .accentColor)
            }
        }
    }
}

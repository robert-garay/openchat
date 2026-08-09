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
            DynamicIsland {
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
                Image(systemName: context.state.status.iconName)
                    .foregroundStyle(context.state.status.iconTint)
            } compactTrailing: {
                Text(context.state.detail)
                    .font(.caption2)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: context.state.status.iconName)
                    .foregroundStyle(context.state.status.iconTint)
            }
        }
    }
}

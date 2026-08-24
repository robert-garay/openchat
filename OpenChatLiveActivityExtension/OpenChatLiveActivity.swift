import WidgetKit
import SwiftUI

@main
struct OpenChatLiveActivity: WidgetBundle {
    var body: some Widget {
        OpenChatLiveActivityWidget()
    }
}

/// The OpenChat ensō-ring mark, tinted per Live Activity status and
/// rotating continuously while a response is generating. Used in every
/// Dynamic Island presentation and the Lock Screen banner so the brand mark
/// stays the single consistent visual across all of them.
struct LiveActivityMark: View {
    let status: OpenChatLiveActivityAttributes.Status

    var body: some View {
        Image("OpenChatMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(status.tintColor)
            .rotationEffect(.degrees(status.elapsed * Self.degreesPerSecond))
            .animation(.linear(duration: 1), value: status.elapsed)
    }

    /// One full rotation every 2 seconds, stepped by the ~1s Live Activity
    /// update cadence from `BackgroundGenerationService.notifyProgress`.
    private static let degreesPerSecond: Double = 180
}

/// The compact Dynamic Island trailing slot: a glanceable timer, matching how
/// Timer/Maps/Uber always put a number there rather than leaving it empty.
struct CompactLiveActivityTimer: View {
    let status: OpenChatLiveActivityAttributes.Status

    var body: some View {
        Group {
            if status.isGenerating {
                Text(timerInterval: (Date.now - status.elapsed)...(Date.now + 3600), countsDown: false)
            } else if case .failed = status {
                Text("!")
            } else if let completedAt = status.completedAt {
                Text(timerInterval: completedAt...(completedAt + 3600), countsDown: false)
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(status.tintColor)
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
                LiveActivityMark(status: context.state.status)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                CompactLiveActivityTimer(status: context.state.status)
            } minimal: {
                LiveActivityMark(status: context.state.status)
                    .frame(width: 18, height: 18)
            }
        }
    }
}

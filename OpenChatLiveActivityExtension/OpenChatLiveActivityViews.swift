import WidgetKit
import SwiftUI

struct OpenChatLiveActivityLockScreenView: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            LiveActivityMark(status: context.state.status)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.conversationTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(context.attributes.modelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            LiveActivityStatusText(status: context.state.status)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct OpenChatLiveActivityExpandedLeading: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        LiveActivityMark(status: context.state.status)
            .frame(width: 28, height: 28)
    }
}

struct OpenChatLiveActivityExpandedTrailing: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        LiveActivityStatusText(status: context.state.status)
    }
}

struct OpenChatLiveActivityExpandedCenter: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        Text(context.attributes.conversationTitle)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
    }
}

struct OpenChatLiveActivityExpandedBottom: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        HStack {
            Text(context.attributes.modelName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

/// Live-ticking elapsed time while generating, or a static status word once
/// finished. Never shown in the compact/minimal Dynamic Island — those stay
/// icon-only.
struct LiveActivityStatusText: View {
    let status: OpenChatLiveActivityAttributes.Status

    var body: some View {
        if status.isGenerating {
            Text(timerInterval: (Date.now - status.elapsed)...(Date.now + 3600), countsDown: false)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else if case .failed = status {
            Text("Response failed")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Response ready")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

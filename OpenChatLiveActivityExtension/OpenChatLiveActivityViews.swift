import WidgetKit
import SwiftUI

struct OpenChatLiveActivityLockScreenView: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
            Image(systemName: context.state.status.iconName)
                .foregroundStyle(context.state.status.iconTint)
            Text(context.attributes.conversationTitle)
                    .font(.headline)
                Spacer()
                Text(context.state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case .generating = context.state.status {
                ProgressView()
                    .tint(.accentColor)
            }
        }
        .padding(.horizontal)
    }
}

struct OpenChatLiveActivityExpandedLeading: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        Image(systemName: context.state.status.iconName)
            .font(.title2)
            .foregroundStyle(context.state.status.iconTint)
    }
}

struct OpenChatLiveActivityExpandedTrailing: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        Text(context.state.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

struct OpenChatLiveActivityExpandedCenter: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        Text(context.attributes.conversationTitle)
            .font(.headline)
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

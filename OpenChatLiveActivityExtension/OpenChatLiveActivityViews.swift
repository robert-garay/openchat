import WidgetKit
import SwiftUI

struct OpenChatLiveActivityLockScreenView: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(iconTint)
                Text(context.attributes.conversationTitle)
                    .font(.headline)
                Spacer()
                Text(context.state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isGenerating {
                ProgressView(value: 0.0)
                    .tint(.accentColor)
            }
        }
        .padding(.horizontal)
    }

    private var isGenerating: Bool {
        if case .generating = context.state.status { return true }
        return false
    }

    private var iconName: String {
        switch context.state.status {
        case .generating: "sparkles"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private var iconTint: Color {
        switch context.state.status {
        case .generating: .accentColor
        case .completed: .green
        case .failed: .red
        }
    }
}

struct OpenChatLiveActivityExpandedLeading: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        Image(systemName: iconName)
            .font(.title2)
            .foregroundStyle(iconTint)
    }

    private var iconName: String {
        switch context.state.status {
        case .generating: "sparkles"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private var iconTint: Color {
        switch context.state.status {
        case .generating: .accentColor
        case .completed: .green
        case .failed: .red
        }
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

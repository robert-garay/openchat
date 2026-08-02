import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let providerTint: Color
    let providerSymbol: String
    let onRetry: () -> Void

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantContent
        case .system:
            EmptyView()
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            MarkdownMessageView(content: message.content, isUserMessage: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: Theme.bubbleCornerRadius, style: .continuous))
        }
    }

    private var assistantContent: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(providerTint.opacity(0.15))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: providerSymbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(providerTint)
                }

            VStack(alignment: .leading, spacing: 8) {
                if message.content.isEmpty && message.isStreaming {
                    TypingIndicatorView()
                        .padding(.top, 6)
                } else {
                    MarkdownMessageView(content: message.content, isUserMessage: false)
                }

                if let errorMessage = message.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text(errorMessage)
                            .font(.caption)
                        Button("Retry", action: onRetry)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.red)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 24)
        }
    }
}

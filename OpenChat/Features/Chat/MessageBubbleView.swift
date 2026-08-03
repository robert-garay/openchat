import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MessageBubbleView: View {
    let message: ChatMessage
    let providerTint: Color
    let providerSymbol: String
    var providerLogoAssetName: String? = nil
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
            VStack(alignment: .trailing, spacing: 8) {
                if !message.imageAttachments.isEmpty {
                    attachmentGallery(message.imageAttachments)
                }
                if !message.content.isEmpty {
                    MarkdownMessageView(content: message.content, isUserMessage: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: Theme.bubbleCornerRadius, style: .continuous))
                }
            }
        }
    }

    private var assistantContent: some View {
        HStack(alignment: .top, spacing: 10) {
            ProviderLogoView(
                logoAssetName: providerLogoAssetName,
                symbolName: providerSymbol,
                tint: providerTint,
                size: 26
            )

            VStack(alignment: .leading, spacing: 8) {
                if message.content.isEmpty && message.isStreaming {
                    TypingIndicatorView()
                        .padding(.top, 6)
                } else if !message.content.isEmpty {
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

    private func attachmentGallery(_ attachments: [ChatImageAttachment]) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(attachments) { attachment in
                #if canImport(UIKit)
                if let uiImage = UIImage(data: attachment.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                #endif
            }
        }
    }
}

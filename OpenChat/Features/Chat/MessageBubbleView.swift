import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MessageBubbleView: View {
    let message: ChatMessage
    let providerTint: Color
    let providerSymbol: String
    var providerLogoAssetName: String? = nil
    var pendingCalendarActions: [CalendarActionProposal] = []
    var calendarActionStatus: String? = nil
    var isApplyingCalendarActions: Bool = false
    var onConfirmCalendarActions: (() -> Void)? = nil
    var onDismissCalendarActions: (() -> Void)? = nil
    var pendingMemoryProposals: [MemoryProposal] = []
    var memoryActionStatus: String? = nil
    var onConfirmMemoryProposals: (() -> Void)? = nil
    var onDismissMemoryProposals: (() -> Void)? = nil
    let onRetry: () -> Void

    #if canImport(UIKit)
    @State private var previewAttachment: ChatImageAttachment?
    #endif

    var body: some View {
        Group {
            switch message.role {
            case .user:
                userBubble
            case .assistant:
                assistantContent
            case .system, .tool:
                EmptyView()
            }
        }
        .contextMenu {
            if !message.content.isEmpty {
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = message.content
                    #endif
                    Haptics.light()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            if !message.reasoningContent.isEmpty {
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = message.reasoningContent
                    #endif
                    Haptics.light()
                } label: {
                    Label("Copy Thinking", systemImage: "brain")
                }
            }
        }
        #if canImport(UIKit)
        .fullScreenCover(item: $previewAttachment) { attachment in
            if let uiImage = UIImage(data: attachment.data) {
                ImagePreviewView(image: uiImage)
            }
        }
        #endif
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 8) {
                if !message.imageAttachments.isEmpty {
                    attachmentGallery(message.imageAttachments, alignment: .trailing)
                }
                if !message.content.isEmpty {
                    MarkdownMessageView(content: message.content, isUserMessage: true)
                        .equatable()
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
                if !message.imageAttachments.isEmpty {
                    attachmentGallery(message.imageAttachments, alignment: .leading)
                }

                if !message.reasoningContent.isEmpty {
                    ThinkingDisclosureView(
                        reasoning: message.reasoningContent,
                        isStreaming: message.isStreaming,
                        answerStarted: !message.content.isEmpty
                    )
                }

                if message.content.isEmpty
                    && message.reasoningContent.isEmpty
                    && message.isStreaming
                    && message.imageAttachments.isEmpty {
                    TypingIndicatorView()
                        .padding(.top, 6)
                } else if !displayContent.isEmpty {
                    MarkdownMessageView(content: displayContent, isUserMessage: false)
                        .equatable()
                }

                if !pendingCalendarActions.isEmpty {
                    calendarConfirmationCard
                } else if let calendarActionStatus, !calendarActionStatus.isEmpty {
                    Text(calendarActionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !pendingMemoryProposals.isEmpty {
                    memoryConfirmationCard
                } else if let memoryActionStatus, !memoryActionStatus.isEmpty {
                    Text(memoryActionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = message.errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        MarkdownMessageView(content: errorMessage, isUserMessage: false)
                            .equatable()
                        Button("Retry", action: onRetry)
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.bordered)
                    }
                }
            }
            Spacer(minLength: 24)
        }
    }

    private var displayContent: String {
        MemoryActionParser.strippingFences(from: CalendarActionParser.strippingFences(from: message.content))
    }

    private var calendarConfirmationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Confirm calendar changes", systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))

            ForEach(pendingCalendarActions) { action in
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.summaryTitle)
                        .font(.caption.weight(.semibold))
                    Text(action.summaryDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button("Apply") {
                    onConfirmCalendarActions?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplyingCalendarActions)

                Button("Discard") {
                    onDismissCalendarActions?()
                }
                .buttonStyle(.bordered)
                .disabled(isApplyingCalendarActions)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var memoryConfirmationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Save to memory?", systemImage: "brain.head.profile")
                .font(.subheadline.weight(.semibold))
            ForEach(pendingMemoryProposals) { proposal in
                Text(proposal.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Save") { onConfirmMemoryProposals?() }
                    .buttonStyle(.borderedProminent)
                Button("Discard") { onDismissMemoryProposals?() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func attachmentGallery(_ attachments: [ChatImageAttachment], alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            ForEach(attachments) { attachment in
                #if canImport(UIKit)
                if let uiImage = UIImage(data: attachment.data) {
                    Button {
                        Haptics.light()
                        previewAttachment = attachment
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260, maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview image")
                    .accessibilityHint("Opens full screen preview with zoom")
                }
                #endif
            }
        }
    }
}

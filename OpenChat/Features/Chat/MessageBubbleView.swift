import SwiftUI
#if canImport(UIKit)
import UIKit
import Photos
#endif

struct MessageBubbleView: View {
    let message: ChatMessage
    let conversation: Conversation
    var pendingCalendarActions: [CalendarActionProposal] = []
    var calendarActionStatus: String? = nil
    var isApplyingCalendarActions: Bool = false
    var onConfirmCalendarActions: (() -> Void)? = nil
    var onDismissCalendarActions: (() -> Void)? = nil
    var pendingRemindersActions: [RemindersActionProposal] = []
    var remindersActionStatus: String? = nil
    var isApplyingRemindersActions: Bool = false
    var onConfirmRemindersActions: (() -> Void)? = nil
    var onDismissRemindersActions: (() -> Void)? = nil
    var pendingContactsActions: [ContactsActionProposal] = []
    var contactsActionStatus: String? = nil
    var isApplyingContactsActions: Bool = false
    var onConfirmContactsActions: (() -> Void)? = nil
    var onDismissContactsActions: (() -> Void)? = nil
    var pendingMemoryProposals: [MemoryProposal] = []
    var memoryActionStatus: String? = nil
    var onConfirmMemoryProposals: (() -> Void)? = nil
    var onDismissMemoryProposals: (() -> Void)? = nil
    var pendingSkillProposals: [SkillProposal] = []
    var skillActionStatus: String? = nil
    var onDismissSkillProposals: (() -> Void)? = nil
    var onSkillProposalSaved: (() -> Void)? = nil
    var pendingRuleProposals: [RuleProposal] = []
    var ruleActionStatus: String? = nil
    var onDismissRuleProposals: (() -> Void)? = nil
    var onRuleProposalSaved: ((UUID) -> Void)? = nil
    var isLastMessage: Bool = false
    let onRetry: () -> Void
    var canEdit: Bool = false
    var onBeginEdit: (() -> Void)? = nil

    #if canImport(UIKit)
    @State private var previewAttachment: ChatImageAttachment?
    @State private var previewDocument: ChatDocumentAttachment?
    @State private var showingTextSelection = false
    @State private var selectionText: String = ""
    @State private var shareAttachment: ChatImageAttachment?
    #endif
    @State private var reviewingSkillProposal: SkillProposal?
    @State private var reviewingRuleProposal: RuleProposal?

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
        #if canImport(UIKit)
        .fullScreenCover(item: $previewAttachment) { attachment in
            ImagePreviewView(
                attachments: ImageGallery.attachments(in: conversation.sortedMessages),
                initialID: attachment.id
            )
        }
        .fullScreenCover(item: $previewDocument) { attachment in
            DocumentPreviewView(attachment: attachment)
        }
        .sheet(isPresented: $showingTextSelection) {
            TextSelectionSheet(text: selectionText)
        }
        .sheet(item: $shareAttachment) { attachment in
            if let uiImage = UIImage(data: attachment.data) {
                ActivityShareSheet(activityItems: [uiImage])
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
                if !message.documentAttachments.isEmpty {
                    documentChipRow(message.documentAttachments, alignment: .trailing)
                }
                if !message.content.isEmpty {
                    userBubbleText
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: Theme.bubbleCornerRadius, style: .continuous))
                        #if canImport(UIKit)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = message.content
                                Haptics.light()
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }

                            if canEdit {
                                Button {
                                    onBeginEdit?()
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                            }

                            Button {
                                Haptics.light()
                                selectionText = message.content
                                showingTextSelection = true
                            } label: {
                                Label("Select", systemImage: "text.cursor")
                            }
                        }
                        #endif
                }
            }
        }
    }

    /// Renders full markdown normally, except for an explicit `/slash-name` invocation
    /// (which is stored verbatim in `message.content`) — there, the leading token is
    /// tinted to mark it as a skill invocation, and the rest is plain text.
    @ViewBuilder
    private var userBubbleText: some View {
        if let token = leadingSlashToken {
            let remainder = String(message.content.dropFirst(token.count + 1))
            (
                Text("/\(token)")
                    .foregroundStyle(Color.yellow)
                    .fontWeight(.semibold)
                + Text(remainder)
                    .foregroundStyle(.white)
            )
            .font(.body)
            .textSelection(.enabled)
        } else {
            Text(message.content)
                .foregroundStyle(.white)
                .textSelection(.enabled)
        }
    }

    private var leadingSlashToken: String? {
        guard message.content.first == "/" else { return nil }
        let afterSlash = message.content.dropFirst()
        let tokenEnd = afterSlash.firstIndex(where: { $0 == " " || $0.isNewline }) ?? afterSlash.endIndex
        let token = afterSlash[afterSlash.startIndex..<tokenEnd]
        guard !token.isEmpty, token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return String(token)
    }

    private var assistantContent: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                if !message.imageAttachments.isEmpty {
                    attachmentGallery(message.imageAttachments, alignment: .leading)
                }
                if !message.documentAttachments.isEmpty {
                    documentChipRow(message.documentAttachments, alignment: .leading)
                }

                if message.content.isEmpty && message.isStreaming && message.imageAttachments.isEmpty {
                    TypingIndicatorView()
                        .padding(.top, 6)
                } else if !displayContent.isEmpty {
                    AssistantMarkdownMessageView(message: message, displayContent: Self.displayContent)
                }

                #if canImport(UIKit)
                if !displayContent.isEmpty {
                    HStack(spacing: 4) {
                        CopyChip(content: message.content)
                        if isLastMessage && !message.isStreaming {
                            RegenerateChip(action: onRetry)
                        }
                        Spacer(minLength: 4)
                        if let responseTimeLabel {
                            Text(responseTimeLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if isLastMessage && !message.isStreaming && message.errorMessage == nil {
                    RegenerateChip(action: onRetry)
                }
                #endif

                if !pendingCalendarActions.isEmpty {
                    calendarConfirmationCard
                } else if let calendarActionStatus, !calendarActionStatus.isEmpty {
                    Text(calendarActionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !pendingRemindersActions.isEmpty {
                    remindersConfirmationCard
                } else if let remindersActionStatus, !remindersActionStatus.isEmpty {
                    Text(remindersActionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !pendingContactsActions.isEmpty {
                    contactsConfirmationCard
                } else if let contactsActionStatus, !contactsActionStatus.isEmpty {
                    Text(contactsActionStatus)
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

                if !pendingSkillProposals.isEmpty {
                    skillProposalCard
                } else if let skillActionStatus, !skillActionStatus.isEmpty {
                    Text(skillActionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !pendingRuleProposals.isEmpty {
                    ruleProposalCard
                } else if let ruleActionStatus, !ruleActionStatus.isEmpty {
                    Text(ruleActionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = message.errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        StaticMarkdownMessageView(content: errorMessage)
                        Button("Retry", action: onRetry)
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.bordered)
                    }
                }
            }
            Spacer(minLength: 4)
        }
    }

    private var displayContent: String { Self.displayContent(message) }

    nonisolated static func displayContent(_ message: ChatMessage) -> String {
        let stripped = RuleActionParser.strippingFences(
            from: MemoryActionParser.strippingFences(
                from: ContactsActionParser.strippingFences(
                    from: RemindersActionParser.strippingFences(
                        from: CalendarActionParser.strippingFences(from: message.content)
                    )
                )
            )
        )
        // Hide bare image placeholders for messages that already have rendered image attachments.
        return message.imageAttachments.isEmpty
            ? stripped
            : GeneratedImageParser.stripImagePlaceholders(from: stripped)
    }

    private var responseTimeLabel: String? {
        guard let seconds = message.responseTimeSeconds else { return nil }
        return String(format: "%.2fs", seconds)
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

    private var remindersConfirmationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Confirm reminders changes", systemImage: "checklist")
                .font(.subheadline.weight(.semibold))

            ForEach(pendingRemindersActions) { action in
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
                    onConfirmRemindersActions?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplyingRemindersActions)

                Button("Discard") {
                    onDismissRemindersActions?()
                }
                .buttonStyle(.bordered)
                .disabled(isApplyingRemindersActions)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var contactsConfirmationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Confirm contacts changes", systemImage: "person.crop.circle.badge.checkmark")
                .font(.subheadline.weight(.semibold))

            ForEach(pendingContactsActions) { action in
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
                    onConfirmContactsActions?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplyingContactsActions)

                Button("Discard") {
                    onDismissContactsActions?()
                }
                .buttonStyle(.bordered)
                .disabled(isApplyingContactsActions)
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

    private var skillProposalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("New skill drafted", systemImage: "bolt.fill")
                .font(.subheadline.weight(.semibold))
            ForEach(pendingSkillProposals) { proposal in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(proposal.name)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("/\(proposal.slashName)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if !proposal.description.isEmpty {
                        Text(proposal.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Button("Review") {
                    reviewingSkillProposal = pendingSkillProposals.first
                }
                .buttonStyle(.borderedProminent)
                Button("Discard") { onDismissSkillProposals?() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .sheet(item: $reviewingSkillProposal) { proposal in
            SkillEditorView(skill: nil, proposal: proposal, onSaved: onSkillProposalSaved)
        }
    }

    private var ruleProposalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("New rule proposed", systemImage: "list.bullet.rectangle")
                .font(.subheadline.weight(.semibold))
            ForEach(pendingRuleProposals) { proposal in
                VStack(alignment: .leading, spacing: 2) {
                    Text(proposal.content)
                        .font(.caption)
                    Text(proposal.scope == .global ? "Every chat" : "This chat")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Review") {
                    reviewingRuleProposal = pendingRuleProposals.first
                }
                .buttonStyle(.borderedProminent)
                Button("Discard") { onDismissRuleProposals?() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .sheet(item: $reviewingRuleProposal) { proposal in
            RuleReviewSheet(proposal: proposal, conversation: conversation, onSaved: onRuleProposalSaved)
        }
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
                    .contextMenu {
                        Button {
                            UIPasteboard.general.image = uiImage
                            Haptics.light()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        Button {
                            shareAttachment = attachment
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            saveToPhotos(uiImage)
                        } label: {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }

                        if message.role == .user && message.content.isEmpty && canEdit {
                            Button {
                                onBeginEdit?()
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                    }
                }
                #endif
            }
        }
    }

    private func documentChipRow(_ attachments: [ChatDocumentAttachment], alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            ForEach(attachments) { attachment in
                Button {
                    Haptics.light()
                    #if canImport(UIKit)
                    previewDocument = attachment
                    #endif
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(attachment.filename)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(Color.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview document \(attachment.filename)")
                .accessibilityHint("Opens document preview")
            }
        }
    }

    #if canImport(UIKit)
    private func saveToPhotos(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in Haptics.error() }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                Task { @MainActor in
                    success ? Haptics.success() : Haptics.error()
                }
            }
        }
    }
    #endif
}

#if canImport(UIKit)
private struct CopyChip: View {
    let content: String

    var body: some View {
        Button {
            UIPasteboard.general.string = content
            Haptics.light()
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy message")
    }
}

private struct RegenerateChip: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Regenerate response")
    }
}

private struct TextSelectionSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PlainTextSelectionView(text: text)
                .navigationTitle("Select Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private struct PlainTextSelectionView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.text = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        if #available(iOS 18.1, *) {
            textView.writingToolsBehavior = .none
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.text = text
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Full-screen editor for a sent user message, matching how ChatGPT and Grok
/// handle editing: the conversation is hidden and the message moves into a
/// composer of its own, so long text and image attachments both have room.
struct EditMessageView: View {
    let message: ChatMessage
    let supportsVision: Bool
    let modelDisplayName: String?
    let trailingMessageCount: Int
    let onCancel: () -> Void
    /// Returns `true` when the edit was applied; the screen dismisses only then.
    let onSave: (String, [ChatImageAttachment]) -> Bool

    @State private var text: String
    @State private var attachments: [ChatImageAttachment]
    @State private var showingTruncationConfirmation = false

    init(
        message: ChatMessage,
        supportsVision: Bool,
        modelDisplayName: String?,
        trailingMessageCount: Int = 0,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, [ChatImageAttachment]) -> Bool
    ) {
        self.message = message
        self.supportsVision = supportsVision
        self.modelDisplayName = modelDisplayName
        self.trailingMessageCount = trailingMessageCount
        self.onCancel = onCancel
        self.onSave = onSave
        _text = State(initialValue: message.content)
        _attachments = State(initialValue: message.imageAttachments)
    }

    private var canSend: Bool {
        !attachments.isEmpty || text.contains { !$0.isWhitespace }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 0)

            AttachmentComposerBox(
                attachments: $attachments,
                documentAttachments: .constant([]),
                supportsVision: supportsVision,
                supportsFiles: false,
                modelDisplayName: modelDisplayName
            ) { onPasteImages, _ in
                composerField(onPasteImages: onPasteImages)
            } buttons: {
                Spacer(minLength: 0)
                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
        .confirmationDialog(
            "Delete later messages?",
            isPresented: $showingTruncationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(trailingMessageCount) message\(trailingMessageCount == 1 ? "" : "s")", role: .destructive) {
                applyEdit()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Editing this message will remove \(trailingMessageCount) later message\(trailingMessageCount == 1 ? "" : "s") and regenerate the reply."
            )
        }
    }

    private var header: some View {
        ZStack {
            Text("Edit message")
                .font(.headline)

            HStack {
                Button {
                    Haptics.light()
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 32, height: 32)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .accessibilityLabel("Cancel editing")

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func composerField(onPasteImages: @escaping ([UIImage]) -> Void) -> some View {
        Group {
            #if canImport(UIKit)
            ComposerTextView(
                text: $text,
                placeholder: "Message",
                minHeight: 22,
                // Roomier than the main composer — the screen exists for this field.
                maxHeight: 240,
                onPasteImages: onPasteImages,
                autoFocus: true
            )
            // Explicit vertical sizing — `.frame(minHeight:maxHeight:)` expands to
            // maxHeight inside a VStack even when the field is short.
            .fixedSize(horizontal: false, vertical: true)
            #else
            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(1...12)
            #endif
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var sendButton: some View {
        Button {
            guard canSend else { return }
            Haptics.light()
            if trailingMessageCount > 0 {
                showingTruncationConfirmation = true
            } else {
                applyEdit()
            }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, canSend ? Color.accentColor : Color(.tertiaryLabel))
        }
        .disabled(!canSend)
        .animation(Theme.springFast, value: canSend)
        .accessibilityLabel("Save and send")
    }

    private func applyEdit() {
        if onSave(text, attachments) {
            onCancel()
        }
    }
}

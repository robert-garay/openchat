import Foundation

/// Builds provider-bound chat turns from persisted messages.
/// Images and documents stay on `ChatMessage`; callers choose whether to include them in the outbound payload.
enum ChatRequestHistory {
    static let omittedImagePlaceholder = "[Image omitted — this model can’t process images]"
    static let notIncludedImagePlaceholder = "[Earlier image not included this turn — ask the user to re-share it if you need to see it]"
    static let omittedDocumentPlaceholder = "[Document omitted — this model can't process documents]"

    /// - Parameter imageSelection: When `includeImages` is true, restricts full-fidelity
    ///   image inclusion to attachment IDs in this set; images outside it are noted as
    ///   available-but-omitted rather than dropped silently. `nil` includes every image
    ///   (existing behavior), used by callers that don't apply the context-management policy.
    static func turns(
        from messages: [ChatMessage],
        includeImages: Bool,
        imageSelection: Set<UUID>? = nil,
        includeDocuments: Bool = true,
        excludingMessageID: UUID? = nil
    ) -> [ChatTurn] {
        messages.compactMap { message in
            if let excludingMessageID, message.id == excludingMessageID { return nil }

            let storedImages = message.imageAttachments
            let images: [ChatImageAttachment]
            let notIncludedCount: Int
            if !includeImages {
                images = []
                notIncludedCount = 0
            } else if let imageSelection {
                images = storedImages.filter { imageSelection.contains($0.id) }
                notIncludedCount = storedImages.count - images.count
            } else {
                images = storedImages
                notIncludedCount = 0
            }
            let storedDocuments = message.documentAttachments
            let documents = includeDocuments ? storedDocuments : []
            var content = message.content

            var omittedNotes: [String] = []
            if !includeImages, !storedImages.isEmpty {
                omittedNotes.append(omittedImagePlaceholder)
            } else if notIncludedCount > 0 {
                omittedNotes.append(notIncludedImagePlaceholder)
            }
            if !includeDocuments, !storedDocuments.isEmpty {
                omittedNotes.append(omittedDocumentPlaceholder)
            }
            if !omittedNotes.isEmpty {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                let notes = omittedNotes.joined(separator: "\n")
                content = trimmed.isEmpty ? notes : trimmed + "\n\n" + notes
            }

            guard !content.isEmpty || !images.isEmpty || !documents.isEmpty else { return nil }
            return ChatTurn(role: message.role, content: content, images: images, documents: documents)
        }
    }
}

import Foundation

/// Builds provider-bound chat turns from persisted messages.
/// Images and documents stay on `ChatMessage`; callers choose whether to include them in the outbound payload.
enum ChatRequestHistory {
    static let omittedImagePlaceholder = "[Image omitted — this model can't process images]"
    static let omittedDocumentPlaceholder = "[Document omitted — this model can't process documents]"

    static func turns(
        from messages: [ChatMessage],
        includeImages: Bool,
        includeDocuments: Bool = true,
        excludingMessageID: UUID? = nil
    ) -> [ChatTurn] {
        messages.compactMap { message in
            if let excludingMessageID, message.id == excludingMessageID { return nil }

            let storedImages = message.imageAttachments
            let images = includeImages ? storedImages : []
            let storedDocuments = message.documentAttachments
            let documents = includeDocuments ? storedDocuments : []
            var content = message.content

            var omittedNotes: [String] = []
            if !includeImages, !storedImages.isEmpty {
                omittedNotes.append(omittedImagePlaceholder)
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

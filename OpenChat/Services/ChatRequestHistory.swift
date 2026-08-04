import Foundation

/// Builds provider-bound chat turns from persisted messages.
/// Images stay on `ChatMessage`; callers choose whether to include them in the outbound payload.
enum ChatRequestHistory {
    static let omittedImagePlaceholder = "[Image omitted — this model can’t process images]"

    static func turns(
        from messages: [ChatMessage],
        includeImages: Bool,
        excludingMessageID: UUID? = nil
    ) -> [ChatTurn] {
        messages.compactMap { message in
            if let excludingMessageID, message.id == excludingMessageID { return nil }

            let storedImages = message.imageAttachments
            let images = includeImages ? storedImages : []
            var content = message.content

            if !includeImages, !storedImages.isEmpty {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    content = omittedImagePlaceholder
                } else {
                    content = trimmed + "\n\n" + omittedImagePlaceholder
                }
            }

            guard !content.isEmpty || !images.isEmpty else { return nil }
            return ChatTurn(role: message.role, content: content, images: images)
        }
    }
}

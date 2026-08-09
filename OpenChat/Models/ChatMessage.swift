import Foundation
import SwiftData

enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    /// OpenAI-compatible tool result role. Not persisted in SwiftData chat history.
    case tool
}

@Model
final class ChatMessage {
    var id: UUID
    var roleRaw: String
    var content: String
    var createdAt: Date
    var isStreaming: Bool
    var errorMessage: String?
    /// Timestamp when streaming finished. Nil for user/system turns or in-progress assistant turns.
    var completedAt: Date?
    /// Provider that generated this assistant turn. Nil for user/system or legacy rows.
    var providerID: String?
    /// Model that generated this assistant turn. Nil for user/system or legacy rows.
    var modelID: String?
    /// JSON-encoded `[ChatImageAttachment]` for multimodal user or assistant turns.
    var attachmentsData: Data?
    /// JSON-encoded `[ChatDocumentAttachment]` for PDF-bearing user turns.
    var documentAttachmentsData: Data?
    var conversation: Conversation?

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    /// Elapsed time between `createdAt` and `completedAt`, in seconds. Nil until the turn finishes.
    var responseTimeSeconds: Double? {
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(createdAt)
    }

    var imageAttachments: [ChatImageAttachment] {
        get {
            guard let attachmentsData else { return [] }
            return (try? JSONDecoder().decode([ChatImageAttachment].self, from: attachmentsData)) ?? []
        }
        set {
            if newValue.isEmpty {
                attachmentsData = nil
            } else {
                attachmentsData = try? JSONEncoder().encode(newValue)
            }
        }
    }

    var documentAttachments: [ChatDocumentAttachment] {
        get {
            guard let documentAttachmentsData else { return [] }
            return (try? JSONDecoder().decode([ChatDocumentAttachment].self, from: documentAttachmentsData)) ?? []
        }
        set {
            if newValue.isEmpty {
                documentAttachmentsData = nil
            } else {
                documentAttachmentsData = try? JSONEncoder().encode(newValue)
            }
        }
    }

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = .now,
        isStreaming: Bool = false,
        errorMessage: String? = nil,
        providerID: String? = nil,
        modelID: String? = nil,
        imageAttachments: [ChatImageAttachment] = [],
        documentAttachments: [ChatDocumentAttachment] = []
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.errorMessage = errorMessage
        self.providerID = providerID
        self.modelID = modelID
        if imageAttachments.isEmpty {
            self.attachmentsData = nil
        } else {
            self.attachmentsData = try? JSONEncoder().encode(imageAttachments)
        }
        if documentAttachments.isEmpty {
            self.documentAttachmentsData = nil
        } else {
            self.documentAttachmentsData = try? JSONEncoder().encode(documentAttachments)
        }
    }
}

extension ChatMessage {
    /// Extracts inline `<image>` / markdown data URI images from `content` and appends
    /// them to `imageAttachments`, then strips bare `{image}` / `<image>` placeholders
    /// when images are present.
    func extractInlineImages() {
        let result = GeneratedImageParser.extractInlineImages(
            from: content,
            hasExistingImages: !imageAttachments.isEmpty
        )
        content = result.text
        if !result.images.isEmpty {
            var existing = imageAttachments
            existing.append(contentsOf: result.images)
            imageAttachments = existing
        }
    }
}

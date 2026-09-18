import Foundation
import SwiftData

enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    /// OpenAI-compatible tool result role. Not persisted in SwiftData chat history.
    case tool
}

/// How a message entered the conversation. Used to show a small indicator on
/// bubbles produced by a spoken voice-mode turn.
enum MessageOrigin: String, Codable, Sendable {
    case text
    case voice
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
    /// True for assistant turns generated while the conversation was not visible.
    var isUnread: Bool
    /// Provider that generated this assistant turn. Nil for user/system or legacy rows.
    var providerID: String?
    /// Model that generated this assistant turn. Nil for user/system or legacy rows.
    var modelID: String?
    /// JSON-encoded `[ChatImageAttachment]` for multimodal user or assistant turns.
    var attachmentsData: Data?
    /// JSON-encoded `[ChatDocumentAttachment]` for PDF-bearing user turns.
    var documentAttachmentsData: Data?
    /// Raw value of `MessageOrigin`. Defaults to `.text` for legacy rows.
    var originRaw: String = MessageOrigin.text.rawValue
    var conversation: Conversation?

    @Transient private var cachedImageAttachments: [ChatImageAttachment]?
    @Transient private var cachedImageAttachmentsData: Data?
    @Transient private var cachedDisplayContent: String?
    @Transient private var cachedDisplayContentSource: String?
    @Transient private var cachedDisplayContentHasAttachments: Bool?

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    var origin: MessageOrigin {
        get { MessageOrigin(rawValue: originRaw) ?? .text }
        set { originRaw = newValue.rawValue }
    }

    /// Elapsed time between `createdAt` and `completedAt`, in seconds. Nil until the turn finishes.
    var responseTimeSeconds: Double? {
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(createdAt)
    }

    var imageAttachments: [ChatImageAttachment] {
        get {
            guard let attachmentsData else {
                cachedImageAttachments = nil
                cachedImageAttachmentsData = nil
                return []
            }
            if cachedImageAttachmentsData == attachmentsData, let cachedImageAttachments {
                return cachedImageAttachments
            }
            let decoded = (try? JSONDecoder().decode([ChatImageAttachment].self, from: attachmentsData)) ?? []
            cachedImageAttachmentsData = attachmentsData
            cachedImageAttachments = decoded
            return decoded
        }
        set {
            cachedImageAttachments = newValue.isEmpty ? nil : newValue
            cachedImageAttachmentsData = nil
            invalidateDisplayContentCache()
            if newValue.isEmpty {
                attachmentsData = nil
            } else {
                attachmentsData = try? JSONEncoder().encode(newValue)
                cachedImageAttachmentsData = attachmentsData
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
        isUnread: Bool = false,
        errorMessage: String? = nil,
        providerID: String? = nil,
        modelID: String? = nil,
        imageAttachments: [ChatImageAttachment] = [],
        documentAttachments: [ChatDocumentAttachment] = [],
        origin: MessageOrigin = .text
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.isUnread = isUnread
        self.errorMessage = errorMessage
        self.providerID = providerID
        self.modelID = modelID
        self.originRaw = origin.rawValue
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
    /// Post-processed assistant content for display (action fences, image placeholders).
    func displayContentForRendering() -> String {
        if cachedDisplayContentSource == content,
           cachedDisplayContentHasAttachments == (attachmentsData != nil),
           let cachedDisplayContent {
            return cachedDisplayContent
        }

        let stripped = RuleActionParser.strippingFences(
            from: MemoryActionParser.strippingFences(from: content)
        )
        let rendered = attachmentsData == nil
            ? stripped
            : GeneratedImageParser.stripImagePlaceholders(from: stripped)
        cachedDisplayContentSource = content
        cachedDisplayContentHasAttachments = attachmentsData != nil
        cachedDisplayContent = rendered
        return rendered
    }

    private func invalidateDisplayContentCache() {
        cachedDisplayContent = nil
        cachedDisplayContentSource = nil
        cachedDisplayContentHasAttachments = nil
    }

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
            imageAttachments = GeneratedImageDeduper.merging(result.images, into: imageAttachments)
        }
    }
}

import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var providerID: String
    var modelID: String
    var systemPrompt: String
    var isTemporary: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage] = []

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        providerID: String,
        modelID: String,
        systemPrompt: String = "",
        isTemporary: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = .now
        self.updatedAt = .now
        self.providerID = providerID
        self.modelID = modelID
        self.systemPrompt = systemPrompt
        self.isTemporary = isTemporary
    }

    var sortedMessages: [ChatMessage] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }

    var hasUserMessages: Bool {
        messages.contains { $0.role == .user }
    }

    var lastMessagePreview: String {
        guard let last = sortedMessages.last(where: { !$0.content.isEmpty || !$0.imageAttachments.isEmpty }) else {
            return "No messages yet"
        }
        if !last.content.isEmpty {
            return last.content
        }
        return last.imageAttachments.count == 1 ? "Photo" : "Photos"
    }
}

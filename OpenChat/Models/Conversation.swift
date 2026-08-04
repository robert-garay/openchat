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
    /// When true, auto title generation must not overwrite a user rename.
    var hasCustomTitle: Bool = false
    /// Pinned chats stay at the top of the sidebar list.
    var isPinned: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage] = []

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        providerID: String,
        modelID: String,
        systemPrompt: String = "",
        isTemporary: Bool = false,
        hasCustomTitle: Bool = false,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = .now
        self.updatedAt = .now
        self.providerID = providerID
        self.modelID = modelID
        self.systemPrompt = systemPrompt
        self.isTemporary = isTemporary
        self.hasCustomTitle = hasCustomTitle
        self.isPinned = isPinned
    }

    var sortedMessages: [ChatMessage] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }

    var hasUserMessages: Bool {
        messages.contains { $0.role == .user }
    }

    /// Toggle temporary mode on the same chat (avoids recreate/selection races).
    func toggleTemporaryMode() {
        isTemporary.toggle()
        title = isTemporary ? "Temporary Chat" : "New Chat"
        hasCustomTitle = false
        updatedAt = .now
    }

    /// Apply a user-chosen title and lock out further auto-generation.
    func rename(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        title = trimmed
        hasCustomTitle = true
        updatedAt = .now
    }

    func togglePinned() {
        isPinned.toggle()
    }

    /// True when the title is still a default placeholder eligible for auto-naming.
    var needsAutoTitle: Bool {
        !isTemporary && !hasCustomTitle && (title == "New Chat" || title == "Temporary Chat")
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

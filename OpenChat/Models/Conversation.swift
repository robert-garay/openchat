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
    /// Structured summary of compacted older messages.
    var compactedSummary: String = ""
    /// Last message ID included in `compactedSummary`.
    var compactedThroughMessageID: UUID?
    /// Denormalized preview so sidebar rows never have to sort messages.
    var previewText: String = ""

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage] = []

    @Relationship(deleteRule: .cascade, inverse: \RuleItem.conversation)
    var rules: [RuleItem] = []

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
        guard messages.count > 1 else { return messages }
        for i in 1..<messages.count {
            if messages[i].createdAt < messages[i - 1].createdAt {
                return messages.sorted { $0.createdAt < $1.createdAt }
            }
        }
        return messages
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

    var hasUserMessages: Bool {
        messages.contains { $0.role == .user }
    }

    var lastMessagePreview: String {
        if !previewText.isEmpty {
            return previewText
        }
        // Fallback for existing conversations before migration.
        guard let last = sortedMessages.last(where: { !$0.content.isEmpty || !$0.imageAttachments.isEmpty }) else {
            return "No messages yet"
        }
        if !last.content.isEmpty {
            return last.content
        }
        return last.imageAttachments.count == 1 ? "Photo" : "Photos"
    }

    /// Update denormalized sidebar fields after a message is added or changed.
    func updateDenormalizedPreview() {
        guard let last = sortedMessages.last(where: { !$0.content.isEmpty || !$0.imageAttachments.isEmpty }) else {
            previewText = ""
            return
        }
        if !last.content.isEmpty {
            previewText = last.content
        } else {
            previewText = last.imageAttachments.count == 1 ? "Photo" : "Photos"
        }
    }
}

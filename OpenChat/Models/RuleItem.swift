import Foundation
import SwiftData

@Model
final class RuleItem {
    var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date

    /// When nil, this rule is global. When set, it belongs to a specific chat.
    var conversation: Conversation?

    init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        conversation: Conversation? = nil
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.conversation = conversation
    }
}

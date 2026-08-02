import Foundation
import SwiftData

enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

@Model
final class ChatMessage {
    var id: UUID
    var roleRaw: String
    var content: String
    var createdAt: Date
    var isStreaming: Bool
    var errorMessage: String?
    var conversation: Conversation?

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = .now,
        isStreaming: Bool = false,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.errorMessage = errorMessage
    }
}

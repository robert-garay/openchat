import Foundation
import SwiftData

enum MemorySource: String, Codable, Sendable, CaseIterable {
    case user, confirmedFromChat, auto
}

@Model
final class MemoryItem {
    var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var pinned: Bool
    var sourceRaw: String
    var source: MemorySource {
        get { MemorySource(rawValue: sourceRaw) ?? .user }
        set { sourceRaw = newValue.rawValue }
    }
    init(id: UUID = UUID(), content: String, createdAt: Date = .now, updatedAt: Date = .now, pinned: Bool = false, source: MemorySource = .user) {
        self.id = id; self.content = content; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.pinned = pinned; self.sourceRaw = source.rawValue
    }
}

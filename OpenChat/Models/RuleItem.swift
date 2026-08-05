import Foundation
import SwiftData

@Model
final class RuleItem {
    var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

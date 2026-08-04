import Foundation
import SwiftData

@Model
final class Skill {
    var id: UUID
    var name: String
    var slashName: String
    var skillDescription: String
    var instructions: String
    var createdAt: Date
    var updatedAt: Date
    var createdFromChatID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        slashName: String,
        skillDescription: String = "",
        instructions: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        createdFromChatID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.slashName = slashName
        self.skillDescription = skillDescription
        self.instructions = instructions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdFromChatID = createdFromChatID
    }
}

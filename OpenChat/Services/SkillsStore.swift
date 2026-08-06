import Foundation
import Observation
import SwiftData

/// Persists the Skills feature toggle (UserDefaults) and CRUD for Skill rows (SwiftData).
@MainActor
@Observable
final class SkillsStore {
    private let enabledKey = "com.openchat.skills.isEnabled"
    private let confirmKey = "com.openchat.skills.requireConfirmation"

    @ObservationIgnored
    private let defaults: UserDefaults

    private(set) var isEnabled: Bool
    private(set) var requireConfirmation: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: enabledKey) == nil {
            isEnabled = false
        } else {
            isEnabled = defaults.bool(forKey: enabledKey)
        }
        if defaults.object(forKey: confirmKey) == nil {
            requireConfirmation = true
        } else {
            requireConfirmation = defaults.bool(forKey: confirmKey)
        }
    }

    func setIsEnabled(_ value: Bool) {
        isEnabled = value
        defaults.set(value, forKey: enabledKey)
    }

    func setRequireConfirmation(_ value: Bool) {
        requireConfirmation = value
        defaults.set(value, forKey: confirmKey)
    }

    func fetchItems(modelContext: ModelContext) throws -> [Skill] {
        try modelContext.fetch(
            FetchDescriptor<Skill>(
                sortBy: [SortDescriptor(\.name)]
            )
        )
    }

    @discardableResult
    func save(
        name: String,
        slashName: String,
        skillDescription: String,
        instructions: String,
        createdFromChatID: UUID? = nil,
        modelContext: ModelContext
    ) throws -> Skill {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSlashName = SkillResolver.normalizeSlashName(slashName)
        guard !trimmedName.isEmpty, !normalizedSlashName.isEmpty else { throw SkillsStoreError.invalidSkill }
        guard !SkillResolver.isReservedSlashName(normalizedSlashName) else { throw SkillsStoreError.reservedSlashName }

        let existing = try fetchItems(modelContext: modelContext)
        guard !existing.contains(where: { $0.slashName == normalizedSlashName }) else {
            throw SkillsStoreError.duplicateSlashName
        }

        let skill = Skill(
            name: trimmedName,
            slashName: normalizedSlashName,
            skillDescription: skillDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
            createdFromChatID: createdFromChatID
        )
        modelContext.insert(skill)
        return skill
    }

    func delete(_ skill: Skill, modelContext: ModelContext) {
        modelContext.delete(skill)
    }

    func clearAll(modelContext: ModelContext) throws {
        for skill in try fetchItems(modelContext: modelContext) {
            modelContext.delete(skill)
        }
    }
}

enum SkillsStoreError: LocalizedError {
    case invalidSkill
    case duplicateSlashName
    case reservedSlashName

    var errorDescription: String? {
        switch self {
        case .invalidSkill: "Skill needs a name and a slash name."
        case .duplicateSlashName: "A skill with this slash name already exists."
        case .reservedSlashName: "This slash name is reserved."
        }
    }
}

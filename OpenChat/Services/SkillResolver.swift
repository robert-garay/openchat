import Foundation

struct SkillMatchable: Sendable, Equatable {
    let slashName: String
    let name: String
    let instructions: String

    init(slashName: String, name: String, instructions: String) {
        self.slashName = slashName
        self.name = name
        self.instructions = instructions
    }

    init(skill: Skill) {
        self.slashName = skill.slashName
        self.name = skill.name
        self.instructions = skill.instructions
    }
}

struct SkillResolution: Sendable, Equatable {
    let skill: SkillMatchable
    let storedMessage: String
}

enum SkillResolver {
    static func normalizeSlashName(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("/") { value.removeFirst() }
        value = value.lowercased()
        value = value.replacingOccurrences(of: " ", with: "")
        value = value.replacingOccurrences(of: "_", with: "-")
        return value
    }

    /// Returns the in-progress slash token while the user is typing a skill.
    /// Bails out cheaply for large pastes so the composer never scans megabytes.
    static func slashQuery(from text: String) -> String? {
        guard text.first == "/" else { return nil }
        // Skill names are short; anything longer is not an in-progress invoke.
        guard text.count <= 64 else { return nil }
        let afterSlash = text.dropFirst()
        if afterSlash.contains(where: { $0 == " " || $0.isNewline }) { return nil }
        return String(afterSlash)
    }

    static func filter(_ skills: [SkillMatchable], query: String) -> [SkillMatchable] {
        let normalizedQuery = normalizeSlashName(query)
        guard !normalizedQuery.isEmpty else {
            return skills.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return skills.filter { $0.slashName.hasPrefix(normalizedQuery) || $0.name.lowercased().hasPrefix(normalizedQuery) }
            .sorted { lhs, rhs in
                let lhsExact = lhs.slashName == normalizedQuery
                let rhsExact = rhs.slashName == normalizedQuery
                if lhsExact != rhsExact { return lhsExact }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    static func resolve(text: String, skills: [SkillMatchable]) -> SkillResolution? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let afterSlash = trimmed.dropFirst()
        let token: String
        let remainder: String
        if let spaceIndex = afterSlash.firstIndex(of: " ") {
            token = String(afterSlash[..<spaceIndex])
            remainder = String(afterSlash[afterSlash.index(after: spaceIndex)...])
        } else {
            token = String(afterSlash)
            remainder = ""
        }
        let normalizedToken = normalizeSlashName(token)
        guard !normalizedToken.isEmpty, let skill = skills.first(where: { $0.slashName == normalizedToken }) else { return nil }
        return SkillResolution(skill: skill, storedMessage: remainder.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func systemBlock(for skill: SkillMatchable) -> String {
        var lines = ["Skill: \(skill.name)"]
        if !skill.instructions.isEmpty { lines.append(skill.instructions) }
        return lines.joined(separator: "\n")
    }

    static func applySelection(skill: SkillMatchable, to text: String) -> String { "/\(skill.slashName) " }
}

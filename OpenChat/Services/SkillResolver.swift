import Foundation

struct SkillMatchable: Sendable, Equatable {
    let slashName: String
    let name: String
    let description: String
    let instructions: String

    init(slashName: String, name: String, description: String = "", instructions: String) {
        self.slashName = slashName
        self.name = name
        self.description = description
        self.instructions = instructions
    }

    init(skill: Skill) {
        self.slashName = skill.slashName
        self.name = skill.name
        self.description = skill.skillDescription
        self.instructions = skill.instructions
    }
}

struct SkillResolution: Sendable, Equatable {
    let skill: SkillMatchable
    /// Full user text as typed, including the `/slash-name` token — stored verbatim so
    /// the sent message can render the token with distinct styling.
    let storedMessage: String
}

enum SkillResolver {
    /// Built-in trigger that starts a guided skill-drafting conversation. Not a stored `Skill`
    /// row, so it's injected into every match list alongside user-defined skills.
    static let skillBuilderSlashName = "skill-builder"

    static let skillBuilderInstructions = """
    The user invoked the built-in skill-builder. Help them draft a new OpenChat skill through \
    conversation: a short display name, a `/slash-name` (lowercase letters, numbers, hyphens), \
    a one-sentence description, and instructions the model should follow whenever the skill is \
    invoked. Ask only what's missing — don't re-ask what the user already gave you. Once you have \
    enough to draft it, call the create_skill tool with your best draft. The user reviews it before \
    it's saved, so it's fine to propose something reasonable rather than interrogating every detail.
    """

    static let skillBuilderSkill = SkillMatchable(
        slashName: skillBuilderSlashName,
        name: "Skill Builder",
        description: "Draft a new OpenChat skill from this conversation.",
        instructions: skillBuilderInstructions
    )

    static func isReservedSlashName(_ normalized: String) -> Bool {
        normalized == skillBuilderSlashName
    }

    /// Prepends the built-in skill-builder entry to a list of user-defined skills.
    static func withBuiltIns(_ skills: [SkillMatchable]) -> [SkillMatchable] {
        [skillBuilderSkill] + skills
    }

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

    /// Resolves a leading `/slash-name` in `text` to a skill. `storedMessage` preserves the
    /// full input verbatim (slash token included) so it can be persisted and rendered as-is —
    /// only the matched skill's instructions are what actually changes model behavior.
    static func resolve(text: String, skills: [SkillMatchable]) -> SkillResolution? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let afterSlash = trimmed.dropFirst()
        let token: String
        if let spaceIndex = afterSlash.firstIndex(of: " ") {
            token = String(afterSlash[..<spaceIndex])
        } else {
            token = String(afterSlash)
        }
        let normalizedToken = normalizeSlashName(token)
        guard !normalizedToken.isEmpty, let skill = skills.first(where: { $0.slashName == normalizedToken }) else { return nil }
        return SkillResolution(skill: skill, storedMessage: trimmed)
    }

    static func systemBlock(for skill: SkillMatchable) -> String {
        var lines = ["Skill: \(skill.name)"]
        if !skill.instructions.isEmpty { lines.append(skill.instructions) }
        return lines.joined(separator: "\n")
    }

    /// Always-visible lightweight index (slash name + name + description only — never
    /// instructions) so the model knows what's available before invoking anything.
    static func index(from skills: [SkillMatchable]) -> String? {
        guard !skills.isEmpty else { return nil }
        let lines = skills.map { skill -> String in
            let summary = skill.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? "- /\(skill.slashName) — \(skill.name)" : "- /\(skill.slashName) — \(skill.name): \(summary)"
        }
        return "## Skills\nAvailable skills the user can invoke with /slash-name, or you can invoke yourself via the invoke_skill tool when relevant:\n\n\(lines.joined(separator: "\n"))"
    }

    static func applySelection(skill: SkillMatchable, to text: String) -> String { "/\(skill.slashName) " }
}

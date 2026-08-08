import Foundation
import Observation
import SwiftData

/// Persists global behavior-steering rules (SwiftData) and feature toggles (UserDefaults).
@MainActor
@Observable
final class RulesStore {
    /// Legacy single-string key from before RuleItem. Cleared after one-time migration.
    static let globalRulesDefaultsKey = "com.openchat.rules.global"

    private let useGlobalRulesKey = "com.openchat.rules.useGlobalRules"
    private let useChatRulesKey = "com.openchat.rules.useChatRules"
    private let allowProposalsFromChatKey = "com.openchat.rules.allowProposalsFromChat"
    private let requireConfirmationKey = "com.openchat.rules.requireConfirmation"

    @ObservationIgnored
    private let defaults: UserDefaults

    private(set) var useGlobalRules: Bool
    private(set) var useChatRules: Bool
    private(set) var allowProposalsFromChat: Bool
    private(set) var requireConfirmation: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: useGlobalRulesKey) == nil {
            useGlobalRules = false
        } else {
            useGlobalRules = defaults.bool(forKey: useGlobalRulesKey)
        }
        if defaults.object(forKey: useChatRulesKey) == nil {
            useChatRules = false
        } else {
            useChatRules = defaults.bool(forKey: useChatRulesKey)
        }
        if defaults.object(forKey: allowProposalsFromChatKey) == nil {
            allowProposalsFromChat = false
        } else {
            allowProposalsFromChat = defaults.bool(forKey: allowProposalsFromChatKey)
        }
        if defaults.object(forKey: requireConfirmationKey) == nil {
            requireConfirmation = true
        } else {
            requireConfirmation = defaults.bool(forKey: requireConfirmationKey)
        }
    }

    func setUseGlobalRules(_ value: Bool) {
        useGlobalRules = value
        defaults.set(value, forKey: useGlobalRulesKey)
    }

    func setUseChatRules(_ value: Bool) {
        useChatRules = value
        defaults.set(value, forKey: useChatRulesKey)
    }

    func setAllowProposalsFromChat(_ value: Bool) {
        allowProposalsFromChat = value
        defaults.set(value, forKey: allowProposalsFromChatKey)
    }

    func setRequireConfirmation(_ value: Bool) {
        requireConfirmation = value
        defaults.set(value, forKey: requireConfirmationKey)
    }

    func fetchItems(modelContext: ModelContext) throws -> [RuleItem] {
        try modelContext.fetch(
            FetchDescriptor<RuleItem>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        )
        .filter { $0.conversation == nil }
    }

    @discardableResult
    func save(content: String, modelContext: ModelContext, conversation: Conversation? = nil) throws -> RuleItem {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RulesStoreError.emptyContent }

        let existing = try scopedItems(conversation: conversation, modelContext: modelContext)
        if let match = findSimilar(existing, trimmed) {
            match.content = trimmed
            match.updatedAt = .now
            return match
        }

        let item = RuleItem(content: trimmed, conversation: conversation)
        modelContext.insert(item)
        return item
    }

    func updateContent(_ item: RuleItem, content: String, modelContext: ModelContext) throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RulesStoreError.emptyContent }

        let others = try scopedItems(conversation: item.conversation, modelContext: modelContext)
            .filter { $0.id != item.id }
        if let match = findSimilar(others, trimmed) {
            modelContext.delete(item)
            match.content = trimmed
            match.updatedAt = .now
            return
        }

        item.content = trimmed
        item.updatedAt = .now
    }

    func delete(_ item: RuleItem, modelContext: ModelContext) {
        modelContext.delete(item)
    }

    func clearAll(modelContext: ModelContext) throws {
        for item in try fetchItems(modelContext: modelContext) {
            modelContext.delete(item)
        }
    }

    /// Joins rule contents for system-prompt injection.
    static func injectionText(from items: [RuleItem]) -> String {
        items
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Context block describing already-saved rules, injected so the model sees existing
    /// state before proposing a new one (mirrors `MemoryStore.contextSection(for:)`).
    static func contextSection(for items: [RuleItem]) -> String? {
        guard !items.isEmpty else { return nil }
        let body = items
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "- \($0)" }
            .joined(separator: "\n")
        guard !body.isEmpty else { return nil }
        return "## Rules\nRules already saved in OpenChat, shown for reference only — this list does not mean they are currently being applied to this chat. Do not propose a new rule that duplicates or re-blends one already listed here.\n\n\(body)"
    }

    /// Rules already saved in the same scope as `conversation` (global when nil, that chat's rules otherwise).
    private func scopedItems(conversation: Conversation?, modelContext: ModelContext) throws -> [RuleItem] {
        if let conversation {
            return conversation.rules
        }
        return try fetchItems(modelContext: modelContext)
    }

    nonisolated static func normalizeContent(_ content: String) -> String {
        content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private func findSimilar(_ items: [RuleItem], _ content: String) -> RuleItem? {
        let normalized = Self.normalizeContent(content)
        return items.first { Self.normalizeContent($0.content) == normalized }
    }

    nonisolated static func shouldAllowRuleProposals(isTemporary: Bool, allowProposalsFromChat: Bool) -> Bool {
        allowProposalsFromChat && !isTemporary
    }

    nonisolated static func modelInstruction() -> String {
        """
        The user enabled rule proposals in OpenChat. A Rule is an instruction about how you \
        should behave, act, or interact going forward — a standing behavior change, not a fact \
        about the user. Examples: "always answer in bullet points", "never use corporate \
        jargon", "write commit messages in the imperative mood". If what you want to save is \
        instead a fact about the user, their environment, or a situation worth recalling (e.g. \
        "I use Xcode 16", "my team ships on Thursdays"), propose a Memory instead, not a Rule. \
        If you're already proposing a Skill or another rule/memory for the same request, don't \
        also propose this unless it captures something genuinely separate — don't restate the \
        same intent across multiple proposals.

        Only propose a rule when you're genuinely confident it's a standing instruction — don't \
        propose speculative or one-off preferences.

        Propose it using:
        ```openchat-rule
        {"content":"...","scope":"global"|"chat"}
        ```
        Always include scope — if it's not clear from context whether this should apply to just \
        this chat or to every chat, ask the user before proposing it. Saved after confirmation \
        unless disabled.
        """
    }

    /// One-time: if the pre–RuleItem UserDefaults string is non-empty and there are no
    /// RuleItems yet, create a RuleItem from it and remove the legacy key.
    func migrateLegacyGlobalRulesIfNeeded(modelContext: ModelContext) {
        let legacy = defaults.string(forKey: Self.globalRulesDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !legacy.isEmpty else { return }

        let existing = (try? fetchItems(modelContext: modelContext)) ?? []
        guard existing.isEmpty else {
            defaults.removeObject(forKey: Self.globalRulesDefaultsKey)
            return
        }

        do {
            _ = try save(content: legacy, modelContext: modelContext)
            try modelContext.save()
            defaults.removeObject(forKey: Self.globalRulesDefaultsKey)
        } catch {
            // Leave the legacy key so a later launch can retry.
        }
    }
}

enum RulesStoreError: LocalizedError {
    case emptyContent

    var errorDescription: String? {
        "Rule cannot be empty."
    }
}

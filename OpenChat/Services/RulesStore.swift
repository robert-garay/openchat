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

    @ObservationIgnored
    private let defaults: UserDefaults

    private(set) var useGlobalRules: Bool
    private(set) var useChatRules: Bool

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
    }

    func setUseGlobalRules(_ value: Bool) {
        useGlobalRules = value
        defaults.set(value, forKey: useGlobalRulesKey)
    }

    func setUseChatRules(_ value: Bool) {
        useChatRules = value
        defaults.set(value, forKey: useChatRulesKey)
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

        let item = RuleItem(content: trimmed, conversation: conversation)
        modelContext.insert(item)
        return item
    }

    func updateContent(_ item: RuleItem, content: String, modelContext: ModelContext) throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RulesStoreError.emptyContent }
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

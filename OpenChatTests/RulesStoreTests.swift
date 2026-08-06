import SwiftData
import XCTest
@testable import OpenChat

@MainActor
final class RulesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: RulesStore!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "com.openchat.tests.rules.\(UUID().uuidString)")
        store = RulesStore(defaults: defaults)
    }

    func testTogglesDefaultToFalseWhenKeysMissing() {
        XCTAssertFalse(store.useGlobalRules)
        XCTAssertFalse(store.useChatRules)
        XCTAssertNil(defaults.object(forKey: "com.openchat.rules.useGlobalRules"))
        XCTAssertNil(defaults.object(forKey: "com.openchat.rules.useChatRules"))
    }

    func testTogglePersistence() {
        store.setUseGlobalRules(true)
        store.setUseChatRules(true)

        let reloaded = RulesStore(defaults: defaults)
        XCTAssertTrue(reloaded.useGlobalRules)
        XCTAssertTrue(reloaded.useChatRules)

        store.setUseGlobalRules(false)
        store.setUseChatRules(false)
        let again = RulesStore(defaults: defaults)
        XCTAssertFalse(again.useGlobalRules)
        XCTAssertFalse(again.useChatRules)
    }

    func testRuleProposalTogglesDefaultWhenKeysMissing() {
        XCTAssertFalse(store.allowProposalsFromChat)
        XCTAssertTrue(store.requireConfirmation)
        XCTAssertNil(defaults.object(forKey: "com.openchat.rules.allowProposalsFromChat"))
        XCTAssertNil(defaults.object(forKey: "com.openchat.rules.requireConfirmation"))
    }

    func testRuleProposalTogglePersistence() {
        store.setAllowProposalsFromChat(true)
        store.setRequireConfirmation(false)

        let reloaded = RulesStore(defaults: defaults)
        XCTAssertTrue(reloaded.allowProposalsFromChat)
        XCTAssertFalse(reloaded.requireConfirmation)
    }

    func testShouldAllowRuleProposals() {
        XCTAssertTrue(RulesStore.shouldAllowRuleProposals(isTemporary: false, allowProposalsFromChat: true))
        XCTAssertFalse(RulesStore.shouldAllowRuleProposals(isTemporary: true, allowProposalsFromChat: true))
        XCTAssertFalse(RulesStore.shouldAllowRuleProposals(isTemporary: false, allowProposalsFromChat: false))
        XCTAssertFalse(RulesStore.shouldAllowRuleProposals(isTemporary: true, allowProposalsFromChat: false))
    }

    func testModelInstructionMentionsFenceAndScope() {
        let instruction = RulesStore.modelInstruction()
        XCTAssertTrue(instruction.contains("openchat-rule"))
        XCTAssertTrue(instruction.contains("scope"))
    }

    func testCRUDAndInjectionText() throws {
        let container = try ModelContainer(
            for: RuleItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let first = try store.save(content: "Be concise.", modelContext: context)
        let second = try store.save(content: "Prefer metric units.", modelContext: context)
        try context.save()

        let fetched = try store.fetchItems(modelContext: context)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(
            RulesStore.injectionText(from: [first, second]),
            "Be concise.\n\nPrefer metric units."
        )

        try store.updateContent(first, content: "Be brief.", modelContext: context)
        XCTAssertEqual(first.content, "Be brief.")

        store.delete(second, modelContext: context)
        try context.save()
        XCTAssertEqual(try store.fetchItems(modelContext: context).count, 1)

        try store.clearAll(modelContext: context)
        try context.save()
        XCTAssertTrue(try store.fetchItems(modelContext: context).isEmpty)
    }

    func testSaveRejectsEmptyContent() throws {
        let container = try ModelContainer(
            for: RuleItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        XCTAssertThrowsError(try store.save(content: "   ", modelContext: context))
    }

    func testMigrateLegacyGlobalRulesCreatesItemAndClearsKey() throws {
        defaults.set("Legacy global rule text", forKey: RulesStore.globalRulesDefaultsKey)

        let container = try ModelContainer(
            for: RuleItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        store.migrateLegacyGlobalRulesIfNeeded(modelContext: context)

        let items = try store.fetchItems(modelContext: context)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.content, "Legacy global rule text")
        XCTAssertNil(defaults.string(forKey: RulesStore.globalRulesDefaultsKey))
    }

    func testMigrateLegacySkipsWhenRulesAlreadyExist() throws {
        defaults.set("Should not migrate", forKey: RulesStore.globalRulesDefaultsKey)

        let container = try ModelContainer(
            for: RuleItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        _ = try store.save(content: "Existing rule", modelContext: context)
        try context.save()

        store.migrateLegacyGlobalRulesIfNeeded(modelContext: context)

        let items = try store.fetchItems(modelContext: context)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.content, "Existing rule")
        XCTAssertNil(defaults.string(forKey: RulesStore.globalRulesDefaultsKey))
    }

    func testMigrateNoopsWhenLegacyEmpty() throws {
        let container = try ModelContainer(
            for: RuleItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        store.migrateLegacyGlobalRulesIfNeeded(modelContext: context)

        XCTAssertTrue(try store.fetchItems(modelContext: context).isEmpty)
    }
}

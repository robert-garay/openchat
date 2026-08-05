import XCTest
@testable import OpenChat

@MainActor
final class ProviderStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: ProviderStore!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "com.openchat.tests.\(UUID().uuidString)")
        store = ProviderStore(defaults: defaults)
    }

    override func tearDown() async throws {
        for provider in store.providers {
            store.removeAPIKey(for: provider)
        }
        try await super.tearDown()
    }

    func testAddFromTemplateAddsExactlyOnce() {
        let template = ProviderTemplate.template(for: "deepseek")!
        store.addFromTemplate(template)
        store.addFromTemplate(template)
        XCTAssertEqual(store.providers.filter { $0.id == "deepseek" }.count, 1)
    }

    func testProviderRequiringKeyIsDisabledUntilKeySet() {
        let template = ProviderTemplate.template(for: "deepseek")!
        store.addFromTemplate(template)
        let provider = store.provider(withID: "deepseek")!

        XCTAssertFalse(store.hasUsableCredentials(provider))
        XCTAssertTrue(store.enabledProviders.isEmpty)

        store.setAPIKey("sk-test", for: provider)
        XCTAssertTrue(store.hasUsableCredentials(provider))
        XCTAssertEqual(store.enabledProviders.first?.id, "deepseek")
    }

    func testCustomEndpointWithoutKeyRequirementIsImmediatelyUsable() {
        store.addCustom(name: "Local Ollama", baseURL: "http://localhost:11434/v1", models: [AIModel(id: "llama3.1", displayName: "llama3.1")], requiresAPIKey: false)
        let provider = store.providers.first!
        XCTAssertTrue(store.hasUsableCredentials(provider))
        XCTAssertEqual(store.enabledProviders.count, 1)
    }

    func testRemoveDeletesProviderAndKey() {
        let template = ProviderTemplate.template(for: "deepseek")!
        store.addFromTemplate(template)
        let provider = store.provider(withID: "deepseek")!
        store.setAPIKey("sk-test", for: provider)

        store.remove(provider)

        XCTAssertNil(store.provider(withID: "deepseek"))
        XCTAssertNil(KeychainStore.get(provider.id))
    }

    func testPersistsAcrossInstancesUsingSameDefaults() {
        store.addFromTemplate(ProviderTemplate.template(for: "qwen")!)
        let reloaded = ProviderStore(defaults: defaults)
        XCTAssertEqual(reloaded.providers.map(\.id), ["qwen"])
    }

    func testRedactedAPIKeyNilWhenMissing() {
        store.addFromTemplate(ProviderTemplate.template(for: "deepseek")!)
        let provider = store.provider(withID: "deepseek")!
        XCTAssertNil(store.redactedAPIKey(for: provider))
    }

    func testRedactedAPIKeyMasksStoredSecret() {
        store.addFromTemplate(ProviderTemplate.template(for: "deepseek")!)
        let provider = store.provider(withID: "deepseek")!
        store.setAPIKey("sk-or-v1-abcdefghijklmnop1234", for: provider)
        XCTAssertEqual(store.redactedAPIKey(for: provider), "sk-••••••••1234")
    }

    func testPickerModelsFallsBackToSavedDefaults() {
        store.addFromTemplate(ProviderTemplate.template(for: "openai")!)
        let provider = store.provider(withID: "openai")!
        store.setAPIKey("sk-test", for: provider)

        let picker = store.pickerModels(for: store.provider(withID: "openai")!)
        XCTAssertFalse(picker.isEmpty)
        XCTAssertEqual(picker.map(\.id), provider.models.map(\.id))
    }

    func testRememberModelPersistsSelection() {
        store.addFromTemplate(ProviderTemplate.template(for: "openai")!)
        let provider = store.provider(withID: "openai")!
        store.setAPIKey("sk-test", for: provider)

        let live = AIModel(id: "gpt-live-test", displayName: "GPT Live", capabilities: [.tools])
        store.rememberModel(live, providerID: "openai")

        XCTAssertEqual(store.provider(withID: "openai")?.models.first?.id, "gpt-live-test")
        XCTAssertEqual(store.model(providerID: "openai", modelID: "gpt-live-test")?.displayName, "GPT Live")
    }

    func testRecordModelUsagePersistsAndRanksMostUsedFirst() {
        store.recordModelUsage(providerID: "openai", modelID: "gpt-4o")
        store.recordModelUsage(providerID: "openai", modelID: "gpt-4o")
        store.recordModelUsage(providerID: "anthropic", modelID: "claude-sonnet")

        XCTAssertEqual(store.modelUsageCount(providerID: "openai", modelID: "gpt-4o"), 2)
        XCTAssertEqual(store.modelUsageCount(providerID: "anthropic", modelID: "claude-sonnet"), 1)
        XCTAssertEqual(store.modelUsageCount(providerID: "openai", modelID: "unused"), 0)

        let reloaded = ProviderStore(defaults: defaults)
        XCTAssertEqual(reloaded.modelUsageCount(providerID: "openai", modelID: "gpt-4o"), 2)

        let ranked = ProviderStore.sortedByUsage(
            ["unused", "claude-sonnet", "gpt-4o"]
        ) { id in
            switch id {
            case "gpt-4o": reloaded.modelUsageCount(providerID: "openai", modelID: id)
            case "claude-sonnet": reloaded.modelUsageCount(providerID: "anthropic", modelID: id)
            default: 0
            }
        }
        XCTAssertEqual(ranked, ["gpt-4o", "claude-sonnet", "unused"])
    }

    func testSortedByUsagePreservesStableOrderForTies() {
        let ranked = ProviderStore.sortedByUsage(["a", "b", "c"]) { _ in 0 }
        XCTAssertEqual(ranked, ["a", "b", "c"])
    }

    func testSeedModelUsageFromConversationsRunsOnce() {
        store.seedModelUsageFromConversationsIfNeeded([
            (providerID: "openai", modelID: "gpt-4o"),
            (providerID: "openai", modelID: "gpt-4o"),
            (providerID: "anthropic", modelID: "claude-sonnet"),
        ])
        XCTAssertEqual(store.modelUsageCount(providerID: "openai", modelID: "gpt-4o"), 2)
        XCTAssertEqual(store.modelUsageCount(providerID: "anthropic", modelID: "claude-sonnet"), 1)

        store.seedModelUsageFromConversationsIfNeeded([
            (providerID: "openai", modelID: "gpt-4o"),
            (providerID: "openai", modelID: "gpt-4o"),
            (providerID: "openai", modelID: "gpt-4o"),
            (providerID: "openai", modelID: "gpt-4o"),
        ])
        XCTAssertEqual(store.modelUsageCount(providerID: "openai", modelID: "gpt-4o"), 2)

        store.recordModelUsage(providerID: "openai", modelID: "gpt-4o")
        XCTAssertEqual(store.modelUsageCount(providerID: "openai", modelID: "gpt-4o"), 3)
    }

    func testRecordModelUsageRemembersLastSelectedForNewChats() {
        store.addFromTemplate(ProviderTemplate.template(for: "openai")!)
        store.addFromTemplate(ProviderTemplate.template(for: "anthropic")!)
        store.setAPIKey("sk-test", for: store.provider(withID: "openai")!)
        store.setAPIKey("sk-test", for: store.provider(withID: "anthropic")!)

        store.recordModelUsage(providerID: "anthropic", modelID: "claude-opus-4-6-20260805")

        let choice = store.defaultModelForNewChat()
        XCTAssertEqual(choice?.providerID, "anthropic")
        XCTAssertEqual(choice?.modelID, "claude-opus-4-6-20260805")

        let reloaded = ProviderStore(defaults: defaults)
        XCTAssertEqual(reloaded.lastSelectedModel?.providerID, "anthropic")
        XCTAssertEqual(reloaded.lastSelectedModel?.modelID, "claude-opus-4-6-20260805")
    }

    func testDefaultModelForNewChatFallsBackWhenLastSelectedUnavailable() {
        store.addFromTemplate(ProviderTemplate.template(for: "openai")!)
        store.setAPIKey("sk-test", for: store.provider(withID: "openai")!)
        store.rememberLastSelectedModel(providerID: "missing", modelID: "gone")

        let choice = store.defaultModelForNewChat()
        XCTAssertEqual(choice?.providerID, "openai")
        XCTAssertEqual(choice?.modelID, store.provider(withID: "openai")?.models.first?.id)
    }

    func testSeedLastSelectedModelOnlyWhenEmpty() {
        store.seedLastSelectedModelIfNeeded(providerID: "openai", modelID: "gpt-4o")
        store.seedLastSelectedModelIfNeeded(providerID: "anthropic", modelID: "claude-sonnet")
        XCTAssertEqual(store.lastSelectedModel?.providerID, "openai")
        XCTAssertEqual(store.lastSelectedModel?.modelID, "gpt-4o")
    }

    func testStarredModelsPersistAndPinOnlyWhenNotFiltering() {
        store.toggleStarredModel(providerID: "openai", modelID: "gpt-4o")
        store.toggleStarredModel(providerID: "anthropic", modelID: "claude-sonnet")
        XCTAssertTrue(store.isModelStarred(providerID: "openai", modelID: "gpt-4o"))

        store.recordModelUsage(providerID: "openai", modelID: "unused")
        store.recordModelUsage(providerID: "openai", modelID: "unused")

        let items = ["unused", "claude-sonnet", "gpt-4o"]
        let unfiltered = ProviderStore.sortedForModelPicker(
            items,
            isFiltering: false,
            isCurrent: { _ in false },
            isStarred: { id in
                id == "gpt-4o" || id == "claude-sonnet"
            },
            usageCount: { id in
                id == "unused" ? 2 : 0
            }
        )
        XCTAssertEqual(unfiltered, ["claude-sonnet", "gpt-4o", "unused"])

        let filtered = ProviderStore.sortedForModelPicker(
            items,
            isFiltering: true,
            isCurrent: { _ in false },
            isStarred: { id in
                id == "gpt-4o" || id == "claude-sonnet"
            },
            usageCount: { id in
                id == "unused" ? 2 : 0
            }
        )
        XCTAssertEqual(filtered, ["unused", "claude-sonnet", "gpt-4o"])

        store.toggleStarredModel(providerID: "openai", modelID: "gpt-4o")
        XCTAssertFalse(store.isModelStarred(providerID: "openai", modelID: "gpt-4o"))

        let reloaded = ProviderStore(defaults: defaults)
        XCTAssertTrue(reloaded.isModelStarred(providerID: "anthropic", modelID: "claude-sonnet"))
        XCTAssertFalse(reloaded.isModelStarred(providerID: "openai", modelID: "gpt-4o"))
    }

    func testCurrentSelectionAlwaysLeadsEvenWhenStarred() {
        let items = ["unused", "claude-sonnet", "gpt-4o", "selected"]
        let unfiltered = ProviderStore.sortedForModelPicker(
            items,
            isFiltering: false,
            isCurrent: { $0 == "selected" },
            isStarred: { $0 == "gpt-4o" || $0 == "claude-sonnet" || $0 == "selected" },
            usageCount: { $0 == "unused" ? 2 : 0 }
        )
        XCTAssertEqual(unfiltered, ["selected", "claude-sonnet", "gpt-4o", "unused"])

        let filtered = ProviderStore.sortedForModelPicker(
            items,
            isFiltering: true,
            isCurrent: { $0 == "selected" },
            isStarred: { $0 == "gpt-4o" },
            usageCount: { $0 == "unused" ? 2 : 0 }
        )
        XCTAssertEqual(filtered, ["selected", "unused", "claude-sonnet", "gpt-4o"])
    }

    func testLastSelectedModelPreservesSlashesInModelID() {
        store.rememberLastSelectedModel(providerID: "openrouter", modelID: "deepseek/deepseek-chat")
        XCTAssertEqual(store.lastSelectedModel?.providerID, "openrouter")
        XCTAssertEqual(store.lastSelectedModel?.modelID, "deepseek/deepseek-chat")
    }
}

final class APIKeyRedactionTests: XCTestCase {
    func testEmptyReturnsEmpty() {
        XCTAssertEqual(APIKeyRedaction.redacted(""), "")
        XCTAssertEqual(APIKeyRedaction.redacted("   "), "")
    }

    func testShortKeysAreFullyMasked() {
        XCTAssertEqual(APIKeyRedaction.redacted("sk-test"), "••••••••")
        XCTAssertEqual(APIKeyRedaction.redacted("12345678"), "••••••••")
    }

    func testLongKeysKeepPrefixAndSuffix() {
        XCTAssertEqual(APIKeyRedaction.redacted("sk-abcdefghij"), "sk-••••••••ghij")
        XCTAssertEqual(APIKeyRedaction.redacted("sk-ant-api03-secretvalue99"), "sk-••••••••ue99")
    }
}

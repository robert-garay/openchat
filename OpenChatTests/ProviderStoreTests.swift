import XCTest
@testable import OpenChat

@MainActor
final class ProviderStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: ProviderStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "com.openchat.tests.\(UUID().uuidString)")
        store = ProviderStore(defaults: defaults)
    }

    override func tearDown() {
        for provider in store.providers {
            store.removeAPIKey(for: provider)
        }
        super.tearDown()
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

    func testConnectOpenRouterAddsStarterModels() {
        store.connectOpenRouter(apiKey: "sk-or-test")

        let provider = store.provider(withID: "openrouter")
        XCTAssertNotNil(provider)
        XCTAssertEqual(store.enabledProviders.map(\.id), ["openrouter"])
        XCTAssertEqual(KeychainStore.get("openrouter"), "sk-or-test")
        XCTAssertFalse(ProviderTemplate.openRouterStarterModels.isEmpty)
        XCTAssertEqual(
            Set(provider!.models.map(\.id)).intersection(Set(ProviderTemplate.openRouterStarterModels.map(\.id))),
            Set(ProviderTemplate.openRouterStarterModels.map(\.id))
        )
        XCTAssertTrue(provider!.models.allSatisfy { !$0.id.hasSuffix(":free") })
    }

    func testConnectOpenRouterIsIdempotentAndKeepsKey() {
        store.connectOpenRouter(apiKey: "sk-or-one")
        store.connectOpenRouter(apiKey: "sk-or-two")

        XCTAssertEqual(store.providers.filter { $0.id == "openrouter" }.count, 1)
        XCTAssertEqual(KeychainStore.get("openrouter"), "sk-or-two")
        XCTAssertEqual(
            Set(store.provider(withID: "openrouter")!.models.map(\.id)),
            Set(ProviderTemplate.openRouterStarterModels.map(\.id))
        )
    }

    func testSyncOpenRouterStarterModelsRestoresMissingDefaults() {
        store.connectOpenRouter(apiKey: "sk-or-sync")
        guard var provider = store.provider(withID: "openrouter") else {
            return XCTFail("OpenRouter should be connected")
        }
        let removedID = ProviderTemplate.openRouterStarterModels[0].id
        provider.models.removeAll { $0.id == removedID }
        store.update(provider)

        store.syncOpenRouterStarterModels()

        let ids = store.provider(withID: "openrouter")!.models.map(\.id)
        XCTAssertTrue(ids.contains(removedID))
        XCTAssertFalse(ids.contains { $0.hasSuffix(":free") })
    }
}

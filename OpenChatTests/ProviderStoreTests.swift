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

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

    func testBootstrapManagedFreeTierInstallsQwenFlash() {
        store.bootstrapManagedFreeTierIfNeeded(apiKey: "sk-or-managed-test")

        let provider = store.provider(withID: ManagedFreeTier.providerID)
        XCTAssertNotNil(provider)
        XCTAssertTrue(provider!.isManagedFreeTier)
        XCTAssertEqual(store.enabledProviders.map(\.id), [ManagedFreeTier.providerID])
        XCTAssertEqual(KeychainStore.get(ManagedFreeTier.providerID), "sk-or-managed-test")
        XCTAssertEqual(provider!.models.map(\.id), [ManagedFreeTier.openRouterModelID])
        XCTAssertEqual(provider!.models.first?.displayName, "Qwen3.7 Flash")
    }

    func testBootstrapManagedFreeTierIsIdempotentAndRefreshesKey() {
        store.bootstrapManagedFreeTierIfNeeded(apiKey: "sk-or-one")
        store.bootstrapManagedFreeTierIfNeeded(apiKey: "sk-or-two")

        XCTAssertEqual(store.providers.filter(\.isManagedFreeTier).count, 1)
        XCTAssertEqual(KeychainStore.get(ManagedFreeTier.providerID), "sk-or-two")
    }

    func testInitBootstrapsManagedFreeTierWhenKeyProvided() {
        let bootstrapped = ProviderStore(defaults: defaults, managedOpenRouterAPIKey: "sk-or-init")
        XCTAssertEqual(bootstrapped.enabledProviders.first?.id, ManagedFreeTier.providerID)
        XCTAssertEqual(KeychainStore.get(ManagedFreeTier.providerID), "sk-or-init")
        bootstrapped.remove(bootstrapped.provider(withID: ManagedFreeTier.providerID)!)
    }

    func testGrantFreeModelsAccessAddsOpenRouterWithFreeModels() {
        store.grantFreeModelsAccess(apiKey: "sk-or-free-test")

        let provider = store.provider(withID: "openrouter")
        XCTAssertNotNil(provider)
        XCTAssertEqual(store.enabledProviders.map(\.id), ["openrouter"])
        XCTAssertEqual(KeychainStore.get("openrouter"), "sk-or-free-test")
        XCTAssertFalse(ProviderTemplate.openRouterFreeModels.isEmpty)
        XCTAssertEqual(
            Set(provider!.models.map(\.id)).intersection(Set(ProviderTemplate.openRouterFreeModels.map(\.id))),
            Set(ProviderTemplate.openRouterFreeModels.map(\.id))
        )
        XCTAssertTrue(provider!.models.allSatisfy { $0.id.hasSuffix(":free") })
    }

    func testSyncGrantedFreeModelsAddsMissingFreeCatalogModels() {
        store.grantFreeModelsAccess(apiKey: "sk-or-sync")
        store.replaceOpenRouterModels([
            OpenRouterCatalogModel(
                id: "google/gemma-4-31b-it:free",
                name: "Google: Gemma 4 31B (free)",
                created: 10,
                contextLength: 262_144,
                huggingFaceID: "google/gemma-4-31B-it",
                promptPrice: 0,
                completionPrice: 0,
                modality: "text->text",
                inputModalities: ["text"],
                outputModalities: ["text"],
                isAlias: false
            ),
            OpenRouterCatalogModel(
                id: "poolside/laguna-s-2.1:free",
                name: "Poolside: Laguna S 2.1 (free)",
                created: 11,
                contextLength: 262_144,
                huggingFaceID: "poolside/Laguna-S-2.1",
                promptPrice: 0,
                completionPrice: 0,
                modality: "text->text",
                inputModalities: ["text"],
                outputModalities: ["text"],
                isAlias: false
            ),
        ])

        store.syncGrantedFreeModels()

        let ids = store.provider(withID: "openrouter")!.models.map(\.id)
        XCTAssertTrue(ids.contains("google/gemma-4-31b-it:free"))
        XCTAssertTrue(ids.contains("poolside/laguna-s-2.1:free"))
    }
}

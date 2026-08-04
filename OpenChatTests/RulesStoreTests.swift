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

    func testDefaultsToEmpty() {
        XCTAssertEqual(store.globalRules, "")
        XCTAssertNil(defaults.string(forKey: RulesStore.globalRulesDefaultsKey))
    }

    func testRoundTripPersistsGlobalRules() {
        store.globalRules = "Be concise and friendly."
        let reloaded = RulesStore(defaults: defaults)
        XCTAssertEqual(reloaded.globalRules, "Be concise and friendly.")
        XCTAssertEqual(
            defaults.string(forKey: RulesStore.globalRulesDefaultsKey),
            "Be concise and friendly."
        )
    }

    func testClearingGlobalRulesPersistsEmptyString() {
        store.globalRules = "Temporary"
        store.globalRules = ""
        XCTAssertEqual(RulesStore(defaults: defaults).globalRules, "")
    }
}

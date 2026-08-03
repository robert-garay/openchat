import XCTest
@testable import OpenChat

@MainActor
final class AgentDataSourceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: AgentDataSourceStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "com.openchat.tests.datasources.\(UUID().uuidString)")
        store = AgentDataSourceStore(defaults: defaults)
    }

    func testDefaultsToAllDisabled() {
        XCTAssertEqual(store.enabledCount, 0)
        XCTAssertFalse(store.hasAcknowledgedFitnessPrivacyNotice)
        for source in AgentDataSource.allCases {
            XCTAssertFalse(store.isEnabled(source))
            XCTAssertFalse(store.isAvailableForAgents(source))
        }
    }

    func testLoadsPersistedEnabledSourcesAndDropsRemovedOnes() {
        defaults.set(["appleHealth", "calendar", "home", "contacts"], forKey: "com.openchat.agentDataSources")
        store = AgentDataSourceStore(defaults: defaults)

        XCTAssertTrue(store.isEnabled(.appleHealth))
        XCTAssertTrue(store.isEnabled(.calendar))
        XCTAssertEqual(store.enabledCount, 2)
        XCTAssertEqual(Set(store.enabledSources.map(\.rawValue)), ["appleHealth", "calendar"])

        let persisted = defaults.array(forKey: "com.openchat.agentDataSources") as? [String] ?? []
        XCTAssertFalse(persisted.contains("home"))
        XCTAssertFalse(persisted.contains("contacts"))
    }

    func testDisablingClearsPersistence() async {
        defaults.set(["photos"], forKey: "com.openchat.agentDataSources")
        store = AgentDataSourceStore(defaults: defaults)
        XCTAssertTrue(store.isEnabled(.photos))

        await store.setEnabled(false, for: .photos)

        XCTAssertFalse(store.isEnabled(.photos))
        let persisted = defaults.array(forKey: "com.openchat.agentDataSources") as? [String] ?? []
        XCTAssertFalse(persisted.contains("photos"))
    }

    func testHealthRequiresFitnessPrivacyNoticeBeforeEnable() async {
        let status = await store.setEnabled(true, for: .appleHealth)
        XCTAssertEqual(status, .notDetermined)
        XCTAssertFalse(store.isEnabled(.appleHealth))

        store.acknowledgeFitnessPrivacyNotice()
        XCTAssertTrue(store.hasAcknowledgedFitnessPrivacyNotice)
        XCTAssertTrue(defaults.bool(forKey: "com.openchat.fitnessPrivacyNoticeAcknowledged"))
    }

    func testSectionsCoverEverySourceExactlyOnce() {
        let grouped = AgentDataSourceSection.allCases.flatMap(\.sources)
        XCTAssertEqual(Set(grouped.map(\.rawValue)), Set(AgentDataSource.allCases.map(\.rawValue)))
        XCTAssertEqual(grouped.count, AgentDataSource.allCases.count)
    }

    func testMVPSourceSet() {
        let ids = Set(AgentDataSource.allCases.map(\.rawValue))
        XCTAssertEqual(ids, [
            "appleHealth",
            "camera",
            "microphone",
            "photos",
            "calendar",
            "notifications",
        ])
    }
}

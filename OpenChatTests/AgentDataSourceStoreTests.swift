@preconcurrency import XCTest
@testable import OpenChat

@MainActor
final class AgentDataSourceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: AgentDataSourceStore!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "com.openchat.tests.datasources.\(UUID().uuidString)")
        store = AgentDataSourceStore(defaults: defaults)
    }

    func testDefaultsToAllDisabled() {
        XCTAssertEqual(store.enabledCount, 0)
        for source in AgentDataSource.allCases {
            XCTAssertFalse(store.isEnabled(source))
            XCTAssertFalse(store.isAvailableForAgents(source))
        }
    }

    func testLoadsPersistedEnabledSourcesAndDropsRemovedOnes() {
        defaults.set(["appleHealth", "calendar", "contacts", "reminders", "photos", "home"], forKey: "com.openchat.agentDataSources")
        store = AgentDataSourceStore(defaults: defaults)

        XCTAssertTrue(store.isEnabled(.photos))
        XCTAssertFalse(store.isEnabled(.camera))
        XCTAssertEqual(store.enabledCount, 1)
        XCTAssertEqual(Set(store.enabledSources.map(\.rawValue)), ["photos"])

        let persisted = defaults.array(forKey: "com.openchat.agentDataSources") as? [String] ?? []
        XCTAssertFalse(persisted.contains("home"))
        XCTAssertFalse(persisted.contains("appleHealth"))
        XCTAssertFalse(persisted.contains("calendar"))
        XCTAssertFalse(persisted.contains("contacts"))
        XCTAssertFalse(persisted.contains("reminders"))
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

    func testSectionsCoverEverySourceExactlyOnce() {
        let grouped = AgentDataSourceSection.allCases.flatMap(\.sources)
        XCTAssertEqual(Set(grouped.map(\.rawValue)), Set(AgentDataSource.allCases.map(\.rawValue)))
        XCTAssertEqual(grouped.count, AgentDataSource.allCases.count)
    }

    func testMVPSourceSet() {
        let ids = Set(AgentDataSource.allCases.map(\.rawValue))
        XCTAssertEqual(ids, [
            "camera",
            "microphone",
            "photos",
            "notifications",
        ])
    }

    func testMarkAvailableForTestingEnablesSource() {
        store.markAvailableForTesting(.camera)
        XCTAssertTrue(store.isEnabled(.camera))
        XCTAssertTrue(store.isAvailableForAgents(.camera))
    }
}

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
        for source in AgentDataSource.allCases {
            XCTAssertFalse(store.isEnabled(source))
            XCTAssertFalse(store.isAvailableForAgents(source))
        }
    }

    func testLoadsPersistedEnabledSources() {
        defaults.set(["appleHealth", "calendar", "not-a-source"], forKey: "com.openchat.agentDataSources")
        store = AgentDataSourceStore(defaults: defaults)

        XCTAssertTrue(store.isEnabled(.appleHealth))
        XCTAssertTrue(store.isEnabled(.calendar))
        XCTAssertFalse(store.isEnabled(.home))
        XCTAssertEqual(store.enabledCount, 2)
        XCTAssertEqual(Set(store.enabledSources.map(\.rawValue)), ["appleHealth", "calendar"])
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
}

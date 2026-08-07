@preconcurrency import XCTest
@testable import OpenChat

final class CalendarActionParserTests: XCTestCase {
    func testParsesCreateUpdateDeleteEnvelope() {
        let markdown = """
        I can move your standup and add lunch.

        ```openchat-calendar
        {"actions":[
          {"type":"create","title":"Lunch","start":"2026-08-04T17:00:00Z","end":"2026-08-04T18:00:00Z","location":"Cafe","isAllDay":false},
          {"type":"update","eventIdentifier":"abc-123","title":"Standup","start":"2026-08-04T14:00:00Z","end":"2026-08-04T14:30:00Z"},
          {"type":"delete","eventIdentifier":"xyz-9"}
        ]}
        ```
        """

        let proposals = CalendarActionParser.parse(markdown)
        XCTAssertEqual(proposals.count, 3)
        XCTAssertEqual(proposals[0].type, .create)
        XCTAssertEqual(proposals[0].title, "Lunch")
        XCTAssertEqual(proposals[1].type, .update)
        XCTAssertEqual(proposals[1].eventIdentifier, "abc-123")
        XCTAssertEqual(proposals[2].type, .delete)
        XCTAssertEqual(proposals[2].eventIdentifier, "xyz-9")
    }

    func testRejectsInvalidCreateWithoutTimes() {
        let markdown = """
        ```openchat-calendar
        {"actions":[{"type":"create","title":"Broken"}]}
        ```
        """
        XCTAssertTrue(CalendarActionParser.parse(markdown).isEmpty)
    }

    func testStripsFencesFromDisplayText() {
        let markdown = """
        Sure — here's the plan.

        ```openchat-calendar
        {"actions":[{"type":"delete","eventIdentifier":"abc"}]}
        ```

        Confirm in the app to apply it.
        """
        let display = CalendarActionParser.strippingFences(from: markdown)
        XCTAssertFalse(display.contains("openchat-calendar"))
        XCTAssertFalse(display.contains("eventIdentifier"))
        XCTAssertTrue(display.contains("Sure — here's the plan."))
        XCTAssertTrue(display.contains("Confirm in the app to apply it."))
    }
}

@MainActor
final class CalendarAccessModeStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: AgentDataSourceStore!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "com.openchat.tests.calendarmode.\(UUID().uuidString)")
        store = AgentDataSourceStore(defaults: defaults)
    }

    func testCalendarModeDefaultsNilAndClearsOnDisable() async {
        XCTAssertNil(store.calendarAccessMode)
        store.markAvailableForTesting(.calendar, calendarMode: .readWrite)
        XCTAssertEqual(store.calendarAccessMode, .readWrite)
        XCTAssertTrue(store.canEditCalendar)

        await store.setEnabled(false, for: .calendar)
        XCTAssertNil(store.calendarAccessMode)
        XCTAssertFalse(store.canEditCalendar)
    }

    func testPersistedReadOnlyCalendarMode() {
        defaults.set(["calendar"], forKey: "com.openchat.agentDataSources")
        defaults.set(CalendarAccessMode.readOnly.rawValue, forKey: "com.openchat.calendarAccessMode")
        store = AgentDataSourceStore(defaults: defaults)

        XCTAssertTrue(store.isEnabled(.calendar))
        XCTAssertEqual(store.calendarAccessMode, .readOnly)
        XCTAssertFalse(store.canEditCalendar)
    }
}

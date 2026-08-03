import XCTest
@testable import OpenChat

@MainActor
final class AgentContextProviderTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: AgentDataSourceStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "com.openchat.tests.agentcontext.\(UUID().uuidString)")
        store = AgentDataSourceStore(defaults: defaults)
    }

    func testCalendarSectionFormatsTodayAndTomorrow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 12))!

        let events = [
            CalendarEventSnapshot(
                title: "Standup",
                start: calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 9))!,
                end: calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 9, minute: 30))!,
                isAllDay: false,
                location: "Zoom"
            ),
            CalendarEventSnapshot(
                title: "Offsite",
                start: calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 0))!,
                end: calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 0))!,
                isAllDay: true,
                location: nil
            ),
        ]

        let section = CalendarContextReader.contextSection(events: events, now: day, calendar: calendar)

        XCTAssertTrue(section.contains("## Calendar"))
        XCTAssertTrue(section.contains("Standup"))
        XCTAssertTrue(section.contains("Zoom"))
        XCTAssertTrue(section.contains("Offsite"))
        XCTAssertTrue(section.contains("All day"))
    }

    func testEmptyCalendarStillProducesSection() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 12))!
        let section = CalendarContextReader.contextSection(events: [], now: day, calendar: calendar)
        XCTAssertTrue(section.contains("No events"))
    }

    func testContextProviderOmitsSourcesThatAreNotAvailable() async {
        var provider = AgentContextProvider(dataSourceStore: store)
        provider.calendarSection = { "## Calendar\n- secret" }
        provider.fitnessSection = { "## Fitness\n- secret" }

        let block = await provider.makeContextBlock()
        XCTAssertNil(block)
    }

    func testContextProviderIncludesEnabledCalendarAndFitness() async {
        store.markAvailableForTesting(.calendar)
        store.markAvailableForTesting(.appleHealth)

        var provider = AgentContextProvider(dataSourceStore: store)
        provider.calendarSection = {
            "## Calendar\n### Today\n- 9:00–10:00: Standup"
        }
        provider.fitnessSection = {
            "## Fitness (Apple Health)\n- Steps today: 4200"
        }

        let block = await provider.makeContextBlock()
        XCTAssertNotNil(block)
        XCTAssertTrue(block!.contains("Standup"))
        XCTAssertTrue(block!.contains("4200"))
        XCTAssertTrue(block!.contains("On-device context"))
    }

    func testContextProviderSkipsDisabledFitnessEvenIfCalendarOn() async {
        store.markAvailableForTesting(.calendar)

        var provider = AgentContextProvider(dataSourceStore: store)
        provider.calendarSection = { "## Calendar\n- Meeting" }
        provider.fitnessSection = { "## Fitness\n- should not appear" }

        let block = await provider.makeContextBlock()
        XCTAssertEqual(block?.contains("Meeting"), true)
        XCTAssertEqual(block?.contains("should not appear"), false)
    }
}

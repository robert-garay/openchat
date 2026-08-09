@preconcurrency import XCTest
@testable import OpenChat

@MainActor
final class AgentContextProviderTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: AgentDataSourceStore!

    override func setUp() async throws {
        try await super.setUp()
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

        let section = CalendarContextReader.contextSection(
            events: events,
            now: day,
            calendar: calendar,
            accessMode: .readOnly
        )

        XCTAssertTrue(section.contains("## Calendar"))
        XCTAssertTrue(section.contains("Standup"))
        XCTAssertTrue(section.contains("Zoom"))
        XCTAssertTrue(section.contains("Offsite"))
        XCTAssertTrue(section.contains("All day"))
        XCTAssertTrue(section.contains("Read only"))
        XCTAssertFalse(section.contains("[id:"))
    }

    func testCalendarSectionIncludesIdsAndEditInstructionsWhenWritable() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 12))!
        let events = [
            CalendarEventSnapshot(
                eventIdentifier: "evt-1",
                title: "Standup",
                start: calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 9))!,
                end: calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 9, minute: 30))!,
                isAllDay: false,
                location: nil
            ),
        ]

        let section = CalendarContextReader.contextSection(
            events: events,
            now: day,
            calendar: calendar,
            accessMode: .readWrite
        )
        XCTAssertTrue(section.contains("[id: evt-1]"))
        XCTAssertTrue(section.contains("openchat-calendar"))
        XCTAssertTrue(section.contains("Can edit"))
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
        provider.calendarSection = { _ in "## Calendar\n- secret" }
        provider.fitnessSection = { "## Fitness\n- secret" }

        let block = await provider.makeContextBlock()
        XCTAssertNil(block)
    }

    func testContextProviderIncludesEnabledCalendarAndFitness() async {
        store.markAvailableForTesting(.calendar, calendarMode: .readOnly)
        store.markAvailableForTesting(.appleHealth)

        var provider = AgentContextProvider(dataSourceStore: store)
        provider.calendarSection = { mode in
            "## Calendar (\(mode.shortLabel))\n### Today\n- 9:00–10:00: Standup"
        }
        provider.fitnessSection = {
            "## Fitness (Apple Health)\n- Steps today: 4200"
        }

        let block = await provider.makeContextBlock()
        XCTAssertNotNil(block)
        XCTAssertTrue(block!.contains("Standup"))
        XCTAssertTrue(block!.contains("4200"))
        XCTAssertTrue(block!.contains("On-device context"))
        XCTAssertTrue(block!.contains("Fitness section"))
        XCTAssertTrue(block!.contains("Read only"))
    }

    func testContextProviderSkipsDisabledFitnessEvenIfCalendarOn() async {
        store.markAvailableForTesting(.calendar)

        var provider = AgentContextProvider(dataSourceStore: store)
        provider.calendarSection = { _ in "## Calendar\n- Meeting" }
        provider.fitnessSection = { "## Fitness\n- should not appear" }

        let block = await provider.makeContextBlock()
        XCTAssertEqual(block?.contains("Meeting"), true)
        XCTAssertEqual(block?.contains("should not appear"), false)
    }

    func testRemindersSectionFormatsDueDatesAndAccessMode() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let due = calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 17))!

        let reminders = [
            ReminderSnapshot(title: "Buy milk", dueDate: due, isCompleted: false, notes: nil),
        ]

        let section = RemindersContextReader.contextSection(reminders: reminders, calendar: calendar, accessMode: .readOnly)
        XCTAssertTrue(section.contains("## Reminders"))
        XCTAssertTrue(section.contains("Buy milk"))
        XCTAssertTrue(section.contains("Read only"))
        XCTAssertFalse(section.contains("[id:"))
    }

    func testRemindersSectionIncludesIdsAndEditInstructionsWhenWritable() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let due = calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 17))!

        let reminders = [
            ReminderSnapshot(reminderIdentifier: "rem-1", title: "Buy milk", dueDate: due, isCompleted: false, notes: nil),
        ]

        let section = RemindersContextReader.contextSection(reminders: reminders, calendar: calendar, accessMode: .readWrite)
        XCTAssertTrue(section.contains("[id: rem-1]"))
        XCTAssertTrue(section.contains("openchat-reminders"))
        XCTAssertTrue(section.contains("Can edit"))
    }

    func testEmptyRemindersStillProducesSection() {
        let section = RemindersContextReader.contextSection(reminders: [], accessMode: .readOnly)
        XCTAssertTrue(section.contains("No open reminders"))
    }

    func testContactsSectionOmitsIdsWhenNotEditable() {
        let contacts = [
            ContactSnapshot(contactIdentifier: "c-1", givenName: "Jane", familyName: "Doe", phoneNumbers: ["555-1234"], emailAddresses: []),
        ]

        let section = ContactsContextReader.contextSection(contacts: contacts, canEdit: false)
        XCTAssertTrue(section.contains("## Contacts"))
        XCTAssertTrue(section.contains("Jane Doe"))
        XCTAssertTrue(section.contains("Read only"))
        XCTAssertFalse(section.contains("[id:"))
    }

    func testContactsSectionIncludesIdsAndEditInstructionsWhenEditable() {
        let contacts = [
            ContactSnapshot(contactIdentifier: "c-1", givenName: "Jane", familyName: "Doe", phoneNumbers: [], emailAddresses: []),
        ]

        let section = ContactsContextReader.contextSection(contacts: contacts, canEdit: true)
        XCTAssertTrue(section.contains("[id: c-1]"))
        XCTAssertTrue(section.contains("openchat-contacts"))
        XCTAssertTrue(section.contains("Can edit"))
    }

    func testEmptyContactsStillProducesSection() {
        let section = ContactsContextReader.contextSection(contacts: [], canEdit: false)
        XCTAssertTrue(section.contains("No contacts"))
    }

    func testContextProviderIncludesEnabledRemindersAndContacts() async {
        store.markAvailableForTesting(.reminders, remindersMode: .readWrite)
        store.markAvailableForTesting(.contacts)

        var provider = AgentContextProvider(dataSourceStore: store)
        provider.remindersSection = { mode in
            "## Reminders (\(mode.shortLabel))\n- Buy milk"
        }
        provider.contactsSection = { canEdit in
            "## Contacts (\(canEdit ? "Can edit" : "Read only"))\n- Jane Doe"
        }

        let block = await provider.makeContextBlock()
        XCTAssertNotNil(block)
        XCTAssertTrue(block!.contains("Buy milk"))
        XCTAssertTrue(block!.contains("Jane Doe"))
        XCTAssertTrue(block!.contains("Reminders section"))
        XCTAssertTrue(block!.contains("Contacts section"))
    }

    func testContextProviderSkipsDisabledRemindersAndContacts() async {
        store.markAvailableForTesting(.calendar)

        var provider = AgentContextProvider(dataSourceStore: store)
        provider.calendarSection = { _ in "## Calendar\n- Meeting" }
        provider.remindersSection = { _ in "## Reminders\n- should not appear" }
        provider.contactsSection = { _ in "## Contacts\n- should not appear" }

        let block = await provider.makeContextBlock()
        XCTAssertEqual(block?.contains("Meeting"), true)
        XCTAssertEqual(block?.contains("should not appear"), false)
    }

    func testContextProviderIncludesMemoryWhenItemsProvided() async {
        var provider = AgentContextProvider(dataSourceStore: store)
        provider.memoryItems = [MemoryItem(content: "Prefers concise answers")]

        let block = await provider.makeContextBlock()
        XCTAssertNotNil(block)
        XCTAssertTrue(block!.contains("## Memory"))
        XCTAssertTrue(block!.contains("Prefers concise answers"))
        XCTAssertTrue(block!.contains("Memory section"))
    }
}

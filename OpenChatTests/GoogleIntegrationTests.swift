@preconcurrency import XCTest
@testable import OpenChat

@MainActor
final class GoogleIntegrationTests: XCTestCase {
    private var accountID: UUID!

    override func setUp() async throws {
        try await super.setUp()
        accountID = UUID()
        GoogleTokenStore.remove(for: accountID)
    }

    override func tearDown() async throws {
        if let accountID {
            GoogleTokenStore.remove(for: accountID)
        }
        try await super.tearDown()
    }

    // MARK: - Token store

    func testTokenStoreRoundTrip() {
        let response = GoogleTokenResponse(
            accessToken: "access-123",
            refreshToken: "refresh-456",
            expiresIn: 3600,
            tokenType: "Bearer",
            scope: "calendar"
        )

        GoogleTokenStore.store(response, for: accountID)

        XCTAssertEqual(GoogleTokenStore.accessToken(for: accountID), "access-123")
        XCTAssertEqual(GoogleTokenStore.refreshToken(for: accountID), "refresh-456")
        XCTAssertFalse(GoogleTokenStore.isExpired(for: accountID))
    }

    func testTokenStoreExpiration() {
        let response = GoogleTokenResponse(
            accessToken: "access-123",
            refreshToken: "refresh-456",
            expiresIn: 0,
            tokenType: "Bearer"
        )

        GoogleTokenStore.store(response, for: accountID)
        XCTAssertTrue(GoogleTokenStore.isExpired(for: accountID))
    }

    func testTokenStoreRemove() {
        let response = GoogleTokenResponse(
            accessToken: "access-123",
            refreshToken: "refresh-456",
            expiresIn: 3600,
            tokenType: "Bearer"
        )
        GoogleTokenStore.store(response, for: accountID)
        GoogleTokenStore.remove(for: accountID)

        XCTAssertNil(GoogleTokenStore.accessToken(for: accountID))
        XCTAssertNil(GoogleTokenStore.refreshToken(for: accountID))
        XCTAssertTrue(GoogleTokenStore.isExpired(for: accountID))
    }

    // MARK: - Calendar context

    func testGoogleCalendarContextSectionFormatsEvents() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 12))!

        let events = [
            GoogleCalendarEventSnapshot(
                eventIdentifier: "evt-1",
                title: "Sprint Planning",
                start: calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 10))!,
                end: calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 11))!,
                isAllDay: false,
                location: "Room A"
            ),
        ]

        let section = GoogleCalendarContextReader.contextSection(
            events: events,
            now: day,
            calendar: calendar,
            includeEditInstructions: false
        )

        XCTAssertNotNil(section)
        XCTAssertTrue(section!.contains("## Google Calendar"))
        XCTAssertTrue(section!.contains("Sprint Planning"))
        XCTAssertTrue(section!.contains("Room A"))
        XCTAssertTrue(section!.contains("Google Calendar"))
    }

    // MARK: - Gmail context

    func testGmailContextSectionFormatsMessages() {
        let messages = [
            GmailMessageSnapshot(
                id: "msg-1",
                threadID: "thread-1",
                subject: "Hello",
                from: "Alice <alice@example.com>",
                snippet: "Quick question",
                date: nil,
                labels: []
            ),
        ]

        let section = GmailContextReader.contextSection(messages: messages)

        XCTAssertNotNil(section)
        XCTAssertTrue(section!.contains("## Gmail"))
        XCTAssertTrue(section!.contains("Alice"))
        XCTAssertTrue(section!.contains("Hello"))
        XCTAssertTrue(section!.contains("Quick question"))
        XCTAssertTrue(section!.contains("read only"))
    }

    // MARK: - Drive context

    func testDriveContextSectionFormatsFiles() {
        let files = [
            GoogleDriveFileSnapshot(
                id: "file-1",
                name: "Project Plan",
                mimeType: "application/vnd.google-apps.document",
                modifiedTime: nil,
                webViewLink: nil,
                size: nil
            ),
        ]

        let section = GoogleDriveContextReader.contextSection(files: files)

        XCTAssertNotNil(section)
        XCTAssertTrue(section!.contains("## Google Drive"))
        XCTAssertTrue(section!.contains("Project Plan"))
        XCTAssertTrue(section!.contains("read only"))
    }

    // MARK: - Context aggregation

    func testGoogleContextProviderAggregatesAccountSections() async {
        let account = GoogleAccount(
            email: "test@example.com",
            name: "Test User",
            connectedScopes: [.calendarReadonly, .gmailReadonly, .driveReadonly],
            enabledApps: [.calendar, .gmail, .drive]
        )

        let block = await GoogleContextProvider.makeContextBlock(
            accounts: [account],
            calendarSection: { _ in "## Google Calendar\n- Event" },
            gmailSection: { _ in "## Gmail\n- Email" },
            driveSection: { _ in "## Google Drive\n- File" }
        )

        XCTAssertNotNil(block)
        XCTAssertTrue(block!.contains("test@example.com"))
        XCTAssertTrue(block!.contains("Google Calendar"))
        XCTAssertTrue(block!.contains("Gmail"))
        XCTAssertTrue(block!.contains("Google Drive"))
    }

    func testGoogleContextProviderOmitsDisabledApps() async {
        let account = GoogleAccount(
            email: "test@example.com",
            connectedScopes: [.calendarReadonly, .gmailReadonly],
            enabledApps: [.calendar]
        )

        let block = await GoogleContextProvider.makeContextBlock(
            accounts: [account],
            calendarSection: { _ in "## Google Calendar\n- Event" },
            gmailSection: { _ in "## Gmail\n- Email" },
            driveSection: { _ in "## Google Drive\n- File" }
        )

        XCTAssertNotNil(block)
        XCTAssertTrue(block!.contains("Google Calendar"))
        XCTAssertFalse(block!.contains("## Gmail"))
        XCTAssertFalse(block!.contains("## Google Drive"))
    }
}

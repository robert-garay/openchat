@preconcurrency import XCTest
@testable import OpenChat

final class RemindersActionParserTests: XCTestCase {
    func testParsesCreateUpdateDeleteEnvelope() {
        let markdown = """
        I can add a reminder and update another.

        ```openchat-reminders
        {"actions":[
          {"type":"create","title":"Buy milk","dueDate":"2026-08-04T17:00:00Z","notes":null},
          {"type":"update","reminderIdentifier":"abc-123","title":"Call mom","dueDate":"2026-08-05T14:00:00Z"},
          {"type":"delete","reminderIdentifier":"xyz-9"}
        ]}
        ```
        """

        let proposals = RemindersActionParser.parse(markdown)
        XCTAssertEqual(proposals.count, 3)
        XCTAssertEqual(proposals[0].type, .create)
        XCTAssertEqual(proposals[0].title, "Buy milk")
        XCTAssertEqual(proposals[1].type, .update)
        XCTAssertEqual(proposals[1].reminderIdentifier, "abc-123")
        XCTAssertEqual(proposals[2].type, .delete)
        XCTAssertEqual(proposals[2].reminderIdentifier, "xyz-9")
    }

    func testRejectsInvalidCreateWithoutTitle() {
        let markdown = """
        ```openchat-reminders
        {"actions":[{"type":"create"}]}
        ```
        """
        XCTAssertTrue(RemindersActionParser.parse(markdown).isEmpty)
    }

    func testStripsFencesFromDisplayText() {
        let markdown = """
        Sure — here's the plan.

        ```openchat-reminders
        {"actions":[{"type":"delete","reminderIdentifier":"abc"}]}
        ```

        Confirm in the app to apply it.
        """
        let display = RemindersActionParser.strippingFences(from: markdown)
        XCTAssertFalse(display.contains("openchat-reminders"))
        XCTAssertFalse(display.contains("reminderIdentifier"))
        XCTAssertTrue(display.contains("Sure — here's the plan."))
        XCTAssertTrue(display.contains("Confirm in the app to apply it."))
    }
}

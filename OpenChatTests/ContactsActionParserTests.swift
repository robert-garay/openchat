@preconcurrency import XCTest
@testable import OpenChat

final class ContactsActionParserTests: XCTestCase {
    func testParsesCreateUpdateDeleteEnvelope() {
        let markdown = """
        I can add a contact and update another.

        ```openchat-contacts
        {"actions":[
          {"type":"create","givenName":"Jane","familyName":"Doe","phoneNumbers":["555-1234"],"emailAddresses":["jane@example.com"]},
          {"type":"update","contactIdentifier":"abc-123","phoneNumbers":["555-9999"]},
          {"type":"delete","contactIdentifier":"xyz-9"}
        ]}
        ```
        """

        let proposals = ContactsActionParser.parse(markdown)
        XCTAssertEqual(proposals.count, 3)
        XCTAssertEqual(proposals[0].type, .create)
        XCTAssertEqual(proposals[0].givenName, "Jane")
        XCTAssertEqual(proposals[0].familyName, "Doe")
        XCTAssertEqual(proposals[1].type, .update)
        XCTAssertEqual(proposals[1].contactIdentifier, "abc-123")
        XCTAssertEqual(proposals[2].type, .delete)
        XCTAssertEqual(proposals[2].contactIdentifier, "xyz-9")
    }

    func testRejectsInvalidCreateWithoutAnyName() {
        let markdown = """
        ```openchat-contacts
        {"actions":[{"type":"create"}]}
        ```
        """
        XCTAssertTrue(ContactsActionParser.parse(markdown).isEmpty)
    }

    func testRejectsUpdateWithoutIdentifier() {
        let markdown = """
        ```openchat-contacts
        {"actions":[{"type":"update","givenName":"Jane"}]}
        ```
        """
        XCTAssertTrue(ContactsActionParser.parse(markdown).isEmpty)
    }

    func testStripsFencesFromDisplayText() {
        let markdown = """
        Sure — here's the plan.

        ```openchat-contacts
        {"actions":[{"type":"delete","contactIdentifier":"abc"}]}
        ```

        Confirm in the app to apply it.
        """
        let display = ContactsActionParser.strippingFences(from: markdown)
        XCTAssertFalse(display.contains("openchat-contacts"))
        XCTAssertFalse(display.contains("contactIdentifier"))
        XCTAssertTrue(display.contains("Sure — here's the plan."))
        XCTAssertTrue(display.contains("Confirm in the app to apply it."))
    }
}

import XCTest
@testable import OpenChat

@MainActor
final class NotificationServiceTests: XCTestCase {
    func testPlainTextStripsBoldAndHeaders() {
        let plain = NotificationService.plainText(fromMarkdown: "# Summary\n**Done!** Here's the plan.")
        XCTAssertFalse(plain.contains("#"))
        XCTAssertFalse(plain.contains("*"))
        XCTAssertTrue(plain.contains("Summary"))
        XCTAssertTrue(plain.contains("Done!"))
    }

    func testPlainTextStripsInlineCodeAndLinks() {
        let plain = NotificationService.plainText(fromMarkdown: "Run `swift build` or see [the docs](https://example.com).")
        XCTAssertFalse(plain.contains("`"))
        XCTAssertFalse(plain.contains("https://example.com"))
        XCTAssertTrue(plain.contains("swift build"))
        XCTAssertTrue(plain.contains("the docs"))
    }

    func testPlainTextFallsBackToOriginalOnPlainInput() {
        let plain = NotificationService.plainText(fromMarkdown: "Just a normal sentence.")
        XCTAssertEqual(plain, "Just a normal sentence.")
    }
}

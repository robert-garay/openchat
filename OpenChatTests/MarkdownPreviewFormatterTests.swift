import XCTest
@testable import OpenChat

final class MarkdownPreviewFormatterTests: XCTestCase {
    func testStripsThematicBreakMarkers() {
        let plain = MarkdownPreviewFormatter.plainText(from: "***")
        XCTAssertEqual(plain, "")
    }

    func testStripsBoldAndItalicMarkers() {
        let plain = MarkdownPreviewFormatter.plainText(from: "**bold** and *italic*")
        XCTAssertEqual(plain, "bold and italic")
    }

    func testStripsHeadingAndListMarkers() {
        let plain = MarkdownPreviewFormatter.plainText(from: """
        # Title
        - Alpha
        - Bravo
        """)
        XCTAssertEqual(plain, "Title Alpha, Bravo")
    }

    func testCollapsesMultilineContentToASingleLine() {
        let plain = MarkdownPreviewFormatter.plainText(from: "Line one\nLine two")
        XCTAssertFalse(plain.contains("\n"))
        XCTAssertEqual(plain, "Line one Line two")
    }
}

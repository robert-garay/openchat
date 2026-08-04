import XCTest
@testable import OpenChat

final class MarkdownContentParserTests: XCTestCase {
    func testParsesHeadingsWithoutLeavingHashMarks() {
        let blocks = MarkdownContentParser.blocks(from: """
        # Title
        ## Subtitle
        ### Section
        Body paragraph.
        """)

        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Title"),
            .heading(level: 2, text: "Subtitle"),
            .heading(level: 3, text: "Section"),
            .paragraph("Body paragraph."),
        ])
    }

    func testParsesListsBlockquotesAndCode() {
        let blocks = MarkdownContentParser.blocks(from: """
        Intro

        - Alpha
        - Bravo

        1. First
        2. Second

        > Quoted line

        ```swift
        print("hi")
        ```

        ---

        Done with **bold** and `code`.
        """)

        XCTAssertEqual(blocks, [
            .paragraph("Intro"),
            .unorderedList(["Alpha", "Bravo"]),
            .orderedList(["First", "Second"]),
            .blockquote("Quoted line"),
            .code(language: "swift", code: "print(\"hi\")"),
            .thematicBreak,
            .paragraph("Done with **bold** and `code`."),
        ])
    }

    func testInlineFormatterKeepsEmphasisAndStripsNothingNeeded() {
        let attributed = MarkdownInlineFormatter.attributed(from: "Hello **world** and `x`")
        let plain = String(attributed.characters)
        XCTAssertTrue(plain.contains("Hello"))
        XCTAssertTrue(plain.contains("world"))
        XCTAssertFalse(plain.contains("**"))
        XCTAssertTrue(plain.contains("x"))
    }

    func testDoesNotTreatHashInWordsAsHeading() {
        let blocks = MarkdownContentParser.blocks(from: "Use C# and look at issue #42 today.")
        XCTAssertEqual(blocks, [.paragraph("Use C# and look at issue #42 today.")])
    }
}

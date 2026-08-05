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

    func testParsesBasicTable() {
        let blocks = MarkdownContentParser.blocks(from: """
        | Name | Value |
        |------|-------|
        | A    | 1     |
        | B    | 2     |
        """)

        XCTAssertEqual(blocks, [
            .table(MarkdownTable(
                headers: ["Name", "Value"],
                rows: [["A", "1"], ["B", "2"]],
                alignments: [.leading, .leading]
            ))
        ])
    }

    func testParsesTableWithPipesAndAlignment() {
        let blocks = MarkdownContentParser.blocks(from: """
        | Item | Count | Price |
        |:-----|:-----:|------:|
        | X    |  10   | 5.00  |
        """)

        XCTAssertEqual(blocks, [
            .table(MarkdownTable(
                headers: ["Item", "Count", "Price"],
                rows: [["X", "10", "5.00"]],
                alignments: [.leading, .center, .trailing]
            ))
        ])
    }

    func testParsesTableWithUnderscoreSeparator() {
        let blocks = MarkdownContentParser.blocks(from: """
        | Foo | Bar |
        |_____|_____|
        | baz | qux |
        """)

        XCTAssertEqual(blocks, [
            .table(MarkdownTable(
                headers: ["Foo", "Bar"],
                rows: [["baz", "qux"]],
                alignments: [.leading, .leading]
            ))
        ])
    }

    func testIgnoresIncompleteTableAsParagraph() {
        let blocks = MarkdownContentParser.blocks(from: "| A | B |\n| C | D |")
        XCTAssertEqual(blocks, [.paragraph("| A | B |\n| C | D |")])
    }

    func testSplitsParagraphBeforeStandaloneTable() {
        let blocks = MarkdownContentParser.blocks(from: """
        Here is the table:
        | A | B |
        |---|---|
        | 1 | 2 |
        """)

        XCTAssertEqual(blocks, [
            .paragraph("Here is the table:"),
            .table(MarkdownTable(
                headers: ["A", "B"],
                rows: [["1", "2"]],
                alignments: [.leading, .leading]
            ))
        ])
    }
}

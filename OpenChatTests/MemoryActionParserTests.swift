import XCTest
@testable import OpenChat
final class MemoryActionParserTests: XCTestCase {
    func testParsesFence() {
        let p = MemoryActionParser.parse("```openchat-memory\n{\"memories\":[\"A\"]}\n```")
        XCTAssertEqual(p.map(\.content), ["A"])
    }
    func testStrips() { XCTAssertFalse(MemoryActionParser.strippingFences(from: "```openchat-memory\nx\n```").contains("openchat-memory")) }

    func testStrippingFencesHidesUnclosedFenceMidStream() {
        let markdown = """
        Before
        ```openchat-memory
        {"memories":["partial still stream
        """
        let stripped = MemoryActionParser.strippingFences(from: markdown)
        XCTAssertEqual(stripped, "Before")
    }

    func testStrippingFencesLeavesPlainTextUnchanged() {
        let markdown = "Just a normal reply with no proposals."
        XCTAssertEqual(MemoryActionParser.strippingFences(from: markdown), markdown)
    }
}

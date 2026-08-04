import XCTest
@testable import OpenChat
final class MemoryActionParserTests: XCTestCase {
    func testParsesFence() {
        let p = MemoryActionParser.parse("```openchat-memory\n{\"memories\":[\"A\"]}\n```")
        XCTAssertEqual(p.map(\.content), ["A"])
    }
    func testStrips() { XCTAssertFalse(MemoryActionParser.strippingFences(from: "```openchat-memory\nx\n```").contains("openchat-memory")) }
}

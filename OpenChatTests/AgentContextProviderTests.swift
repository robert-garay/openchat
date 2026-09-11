@preconcurrency import XCTest
@testable import OpenChat

@MainActor
final class AgentContextProviderTests: XCTestCase {
    func testContextProviderOmitsBlockWhenMemoryIsEmpty() async {
        let provider = AgentContextProvider()
        let block = await provider.makeContextBlock()
        XCTAssertNil(block)
    }

    func testContextProviderIncludesMemoryWhenItemsProvided() async {
        var provider = AgentContextProvider()
        provider.memoryItems = [MemoryItem(content: "Prefers concise answers")]

        let block = await provider.makeContextBlock()
        XCTAssertNotNil(block)
        XCTAssertTrue(block!.contains("## Memory"))
        XCTAssertTrue(block!.contains("Prefers concise answers"))
        XCTAssertTrue(block!.contains("Memory section"))
        XCTAssertFalse(block!.contains("Calendar"))
        XCTAssertFalse(block!.contains("Reminders"))
        XCTAssertFalse(block!.contains("Contacts"))
        XCTAssertFalse(block!.contains("Fitness"))
    }
}

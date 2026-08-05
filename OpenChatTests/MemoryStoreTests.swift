import XCTest
import SwiftData
@testable import OpenChat

@MainActor final class MemoryStoreTests: XCTestCase {
    func testDefaults() { let s = MemoryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!); XCTAssertFalse(s.useInChats); XCTAssertTrue(s.requireConfirmation) }
    func testTemporarySkips() { XCTAssertFalse(MemoryStore.shouldUseMemory(isTemporary: true, useInChats: true)) }

    func testInjectionItemsOrdersByUpdatedAt() {
        let old = MemoryItem(content: "Old", updatedAt: .distantPast)
        let recent = MemoryItem(content: "Recent", updatedAt: .now)
        let store = MemoryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let result = store.injectionItems(from: [old, recent])
        XCTAssertEqual(result.map(\.content), ["Recent", "Old"])
    }

    func testInjectionItemsRespectsCountLimit() {
        let items = (1...50).map { MemoryItem(content: String($0)) }
        let store = MemoryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let result = store.injectionItems(from: items)
        XCTAssertEqual(result.count, MemoryStore.maxInjectionItems)
    }

    func testInjectionItemsRespectsCharacterLimit() {
        let long = String(repeating: "a", count: 5000)
        let items = [
            MemoryItem(content: long, updatedAt: .now),
            MemoryItem(content: long, updatedAt: .now.addingTimeInterval(-1)),
        ]
        let store = MemoryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let result = store.injectionItems(from: items)
        // Each line is "- " + 5000 chars + "\n" = 5003 chars. Two would exceed 8000.
        XCTAssertEqual(result.count, 1)
    }
}

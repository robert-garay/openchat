import XCTest
import SwiftData
@testable import OpenChat
@MainActor final class MemoryStoreTests: XCTestCase {
    func testDefaults() { let s = MemoryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!); XCTAssertFalse(s.useInChats); XCTAssertTrue(s.requireConfirmation) }
    func testTemporarySkips() { XCTAssertFalse(MemoryStore.shouldUseMemory(isTemporary: true, useInChats: true)) }
}

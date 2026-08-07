import XCTest
@testable import OpenChat

final class EffortLevelTests: XCTestCase {
    func testEffortLevelRawValues() {
        XCTAssertEqual(EffortLevel.low.rawValue, "low")
        XCTAssertEqual(EffortLevel.medium.rawValue, "medium")
        XCTAssertEqual(EffortLevel.high.rawValue, "high")
    }

    func testEffortLevelIndexRoundTrip() {
        XCTAssertEqual(EffortLevel(index: 0), .low)
        XCTAssertEqual(EffortLevel(index: 1), .medium)
        XCTAssertEqual(EffortLevel(index: 2), .high)
        XCTAssertNil(EffortLevel(index: -1))
        XCTAssertNil(EffortLevel(index: 3))
    }

    func testEffortLevelDisplayNames() {
        XCTAssertEqual(EffortLevel.low.displayName, "Low")
        XCTAssertEqual(EffortLevel.medium.displayName, "Medium")
        XCTAssertEqual(EffortLevel.high.displayName, "High")
    }

    func testConversationEffortLevelDefaultsToMedium() {
        let conversation = Conversation(providerID: "p", modelID: "m")
        XCTAssertEqual(conversation.effortLevel, .medium)
    }

    func testConversationEffortLevelPersistence() {
        let conversation = Conversation(providerID: "p", modelID: "m")
        conversation.effortLevel = .high
        XCTAssertEqual(conversation.effortLevelRawValue, "high")
        XCTAssertEqual(conversation.effortLevel, .high)
    }
}

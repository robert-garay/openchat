import XCTest
@testable import OpenChat

final class EffortLevelTests: XCTestCase {
    func testEffortLevelRawValues() {
        XCTAssertEqual(EffortLevel.none.rawValue, "none")
        XCTAssertEqual(EffortLevel.minimal.rawValue, "minimal")
        XCTAssertEqual(EffortLevel.low.rawValue, "low")
        XCTAssertEqual(EffortLevel.medium.rawValue, "medium")
        XCTAssertEqual(EffortLevel.high.rawValue, "high")
        XCTAssertEqual(EffortLevel.xhigh.rawValue, "xhigh")
        XCTAssertEqual(EffortLevel.max.rawValue, "max")
    }

    func testEffortLevelIndexRoundTrip() {
        XCTAssertEqual(EffortLevel(index: 0), EffortLevel.none)
        XCTAssertEqual(EffortLevel(index: 1), EffortLevel.minimal)
        XCTAssertEqual(EffortLevel(index: 2), EffortLevel.low)
        XCTAssertEqual(EffortLevel(index: 3), EffortLevel.medium)
        XCTAssertEqual(EffortLevel(index: 4), EffortLevel.high)
        XCTAssertEqual(EffortLevel(index: 5), EffortLevel.xhigh)
        XCTAssertEqual(EffortLevel(index: 6), EffortLevel.max)
        XCTAssertNil(EffortLevel(index: -1))
        XCTAssertNil(EffortLevel(index: 7))
    }

    func testEffortLevelDisplayNames() {
        XCTAssertEqual(EffortLevel.none.displayName, "Off")
        XCTAssertEqual(EffortLevel.minimal.displayName, "Minimal")
        XCTAssertEqual(EffortLevel.low.displayName, "Low")
        XCTAssertEqual(EffortLevel.medium.displayName, "Medium")
        XCTAssertEqual(EffortLevel.high.displayName, "High")
        XCTAssertEqual(EffortLevel.xhigh.displayName, "Max+")
        XCTAssertEqual(EffortLevel.max.displayName, "Max")
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

    func testEffortLevelInferenceForGPT56Sol() {
        let levels = EffortLevel.inferred(for: "openai/gpt-5.6-sol", modelName: "gpt-5.6-sol")
        XCTAssertEqual(levels, [.none, .low, .medium, .high, .xhigh, .max])
    }

    func testEffortLevelInferenceForO3Mini() {
        let levels = EffortLevel.inferred(for: "o3-mini", modelName: "o3-mini")
        XCTAssertEqual(levels, [.low, .medium, .high, .xhigh])
    }

    func testEffortLevelInferenceForDeepSeek() {
        let levels = EffortLevel.inferred(for: "deepseek-reasoner", modelName: "DeepSeek Reasoner")
        XCTAssertEqual(levels, [.high, .max])
    }

    func testEffortLevelInferenceForGemini3() {
        let levels = EffortLevel.inferred(for: "gemini-3.5-flash", modelName: "Gemini 3.5 Flash")
        XCTAssertEqual(levels, [.minimal, .low, .medium, .high])
    }

    func testAIModelSupportedEffortLevels() {
        let model = AIModel(id: "gpt-5.6-sol", displayName: "GPT-5.6 Sol", capabilities: [.effort])
        XCTAssertTrue(model.canDisableReasoning)
        XCTAssertEqual(model.supportedEffortLevels, [.none, .low, .medium, .high, .xhigh, .max])
    }
}

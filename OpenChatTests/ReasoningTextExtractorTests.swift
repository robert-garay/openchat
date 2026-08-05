import XCTest
@testable import OpenChat

final class ReasoningTextExtractorTests: XCTestCase {
    func testExtractSplitsThinkBlockFromAnswer() {
        let text = "<think>plan the steps</think>\n\nHere is the answer."
        let result = ReasoningTextExtractor.extract(from: text)

        XCTAssertEqual(result?.reasoning, "plan the steps")
        XCTAssertEqual(result?.content, "Here is the answer.")
    }

    func testExtractReturnsNilWithoutThinkTags() {
        XCTAssertNil(ReasoningTextExtractor.extract(from: "Just a normal reply."))
    }

    func testExtractHandlesUnclosedThinkWhileStreaming() {
        let result = ReasoningTextExtractor.extract(from: "<think>still thinking")
        XCTAssertEqual(result?.reasoning, "still thinking")
        XCTAssertEqual(result?.content, "")
    }

    func testStreamSplitterSeparatesTagsAcrossChunks() {
        var splitter = ThinkTagStreamSplitter()

        let first = splitter.push("<th")
        XCTAssertEqual(first.reasoning, "")
        XCTAssertEqual(first.content, "")

        let second = splitter.push("ink>reason")
        XCTAssertEqual(second.reasoning, "reason")
        XCTAssertEqual(second.content, "")

        let third = splitter.push("ing</thi")
        XCTAssertEqual(third.reasoning, "ing")
        XCTAssertEqual(third.content, "")

        let fourth = splitter.push("nk>\nAnswer")
        XCTAssertEqual(fourth.reasoning, "")
        XCTAssertEqual(fourth.content, "\nAnswer")

        let trailing = splitter.finish()
        XCTAssertEqual(trailing.reasoning, "")
        XCTAssertEqual(trailing.content, "")
    }

    func testMessageStoresReasoningContent() {
        let message = ChatMessage(
            role: .assistant,
            content: "Answer",
            reasoningContent: "Because reasons"
        )
        XCTAssertEqual(message.reasoningContent, "Because reasons")
        XCTAssertEqual(message.content, "Answer")
    }

    func testChatStreamEventReasoningCase() {
        let event = ChatStreamEvent.reasoning("step 1")
        XCTAssertEqual(event, .reasoning("step 1"))
    }

    func testCompletionResultTracksReasoning() {
        let result = ChatCompletionResult(text: "hi", reasoning: "thought")
        XCTAssertTrue(result.hasReasoning)
        XCTAssertEqual(result.reasoning, "thought")
    }

    func testAIModelSupportsReasoningCapability() {
        let model = AIModel(
            id: "deepseek-reasoner",
            displayName: "R1",
            capabilities: [.reasoning]
        )
        XCTAssertTrue(model.supportsReasoning)
    }
}

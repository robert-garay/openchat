import XCTest
@testable import OpenChat

final class ChatMessageMarkdownSourceTests: XCTestCase {
    @MainActor
    func testInitialSnapshotIsYielded() async {
        let message = ChatMessage(role: .assistant, content: "Hello", isStreaming: true)
        let source = ChatMessageMarkdownSource(message: message)
        var iterator = source.text.makeAsyncIterator()

        let first = await iterator.next()

        XCTAssertEqual(first, "Hello")
    }

    @MainActor
    func testMutationYieldsNewSnapshotWhileStreaming() async {
        let message = ChatMessage(role: .assistant, content: "Hel", isStreaming: true)
        let source = ChatMessageMarkdownSource(message: message)
        var iterator = source.text.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, "Hel")

        message.content = "Hello"
        let second = await iterator.next()

        XCTAssertEqual(second, "Hello")
    }

    @MainActor
    func testStreamFinishesWhenStreamingEnds() async {
        let message = ChatMessage(role: .assistant, content: "Hello", isStreaming: true)
        let source = ChatMessageMarkdownSource(message: message)
        var iterator = source.text.makeAsyncIterator()
        _ = await iterator.next()

        message.isStreaming = false
        let final = await iterator.next()
        XCTAssertEqual(final, "Hello")

        let afterFinish = await iterator.next()
        XCTAssertNil(afterFinish)
    }

    @MainActor
    func testNonStreamingMessageFinishesImmediately() async {
        let message = ChatMessage(role: .assistant, content: "Done", isStreaming: false)
        let source = ChatMessageMarkdownSource(message: message)
        var iterator = source.text.makeAsyncIterator()

        let first = await iterator.next()
        XCTAssertEqual(first, "Done")

        let next = await iterator.next()
        XCTAssertNil(next)
    }

    @MainActor
    func testCustomSnapshotTransformIsApplied() async {
        let message = ChatMessage(role: .assistant, content: "raw", isStreaming: false)
        let source = ChatMessageMarkdownSource(message: message) { _ in "transformed" }
        var iterator = source.text.makeAsyncIterator()

        let first = await iterator.next()

        XCTAssertEqual(first, "transformed")
    }
}

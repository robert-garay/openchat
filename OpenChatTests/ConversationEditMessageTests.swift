import XCTest
@testable import OpenChat

final class ConversationEditMessageTests: XCTestCase {
    private func makeMessage(_ role: MessageRole, _ content: String, secondsOffset: Double) -> ChatMessage {
        ChatMessage(role: role, content: content, createdAt: Date(timeIntervalSince1970: secondsOffset))
    }

    func testMessagesAfterReturnsEmptyWhenMessageIsLast() throws {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let first = makeMessage(.user, "Hi", secondsOffset: 0)
        let second = makeMessage(.assistant, "Hello", secondsOffset: 1)
        first.conversation = conversation
        second.conversation = conversation
        conversation.messages = [first, second]

        XCTAssertTrue(conversation.messages(after: second).isEmpty)
    }

    func testMessagesAfterReturnsSuffixWhenMessageIsInMiddle() throws {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let first = makeMessage(.user, "Hi", secondsOffset: 0)
        let second = makeMessage(.assistant, "Hello", secondsOffset: 1)
        let third = makeMessage(.user, "Follow up", secondsOffset: 2)
        let fourth = makeMessage(.assistant, "Answer", secondsOffset: 3)
        for message in [first, second, third, fourth] {
            message.conversation = conversation
        }
        conversation.messages = [first, second, third, fourth]

        let result = conversation.messages(after: second)
        XCTAssertEqual(result.map(\.id), [third.id, fourth.id])
    }

    func testMessagesAfterReturnsEmptyWhenMessageNotInConversation() throws {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let first = makeMessage(.user, "Hi", secondsOffset: 0)
        first.conversation = conversation
        conversation.messages = [first]

        let outsider = makeMessage(.user, "Not here", secondsOffset: 5)

        XCTAssertTrue(conversation.messages(after: outsider).isEmpty)
    }

    func testMessagesAfterWithMultiplePairsReturnsOnlyTrailingOnes() throws {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let messages = (0..<6).map { index -> ChatMessage in
            let role: MessageRole = index.isMultiple(of: 2) ? .user : .assistant
            return makeMessage(role, "Message \(index)", secondsOffset: Double(index))
        }
        for message in messages {
            message.conversation = conversation
        }
        conversation.messages = messages

        let result = conversation.messages(after: messages[2])
        XCTAssertEqual(result.map(\.id), messages[3...5].map(\.id))
    }
}

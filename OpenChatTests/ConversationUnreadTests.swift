import XCTest
@testable import OpenChat

final class ConversationUnreadTests: XCTestCase {
    func testNewAssistantMessageDefaultsToRead() {
        let message = ChatMessage(role: .assistant, content: "Hello")
        XCTAssertFalse(message.isUnread)
    }

    func testNewUserMessageDefaultsToRead() {
        let message = ChatMessage(role: .user, content: "Hi")
        XCTAssertFalse(message.isUnread)
    }

    func testHasUnreadMessagesTrueWhenAnyMessageUnread() {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let read = ChatMessage(role: .assistant, content: "Read")
        let unread = ChatMessage(role: .assistant, content: "Unread")
        unread.isUnread = true
        read.conversation = conversation
        unread.conversation = conversation
        conversation.messages = [read, unread]

        XCTAssertTrue(conversation.hasUnreadMessages)
    }

    func testHasUnreadMessagesFalseWhenAllRead() {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let message = ChatMessage(role: .assistant, content: "Read")
        message.conversation = conversation
        conversation.messages = [message]

        XCTAssertFalse(conversation.hasUnreadMessages)
    }

    func testMarkAllReadClearsUnreadFlag() {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let first = ChatMessage(role: .assistant, content: "One")
        let second = ChatMessage(role: .user, content: "Two")
        first.isUnread = true
        first.conversation = conversation
        second.conversation = conversation
        conversation.messages = [first, second]

        conversation.markAllRead()

        XCTAssertFalse(first.isUnread)
        XCTAssertFalse(second.isUnread)
        XCTAssertFalse(conversation.hasUnreadMessages)
    }
}

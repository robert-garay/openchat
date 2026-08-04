import XCTest
@testable import OpenChat

final class ConversationTemporaryChatTests: XCTestCase {
    func testNewConversationDefaultsToPersisted() throws {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        XCTAssertFalse(conversation.isTemporary)
        XCTAssertEqual(conversation.title, "New Chat")
        XCTAssertFalse(conversation.hasCustomTitle)
        XCTAssertFalse(conversation.isPinned)
        XCTAssertTrue(conversation.needsAutoTitle)
        XCTAssertFalse(conversation.hasUserMessages)
    }

    func testTemporaryConversationKeepsExplicitTitle() throws {
        let conversation = Conversation(
            title: "Temporary Chat",
            providerID: "openai",
            modelID: "gpt-4o",
            isTemporary: true
        )
        XCTAssertTrue(conversation.isTemporary)
        XCTAssertEqual(conversation.title, "Temporary Chat")
    }

    func testToggleTemporaryFlipsFlagAndTitleInPlace() throws {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let id = conversation.id

        conversation.toggleTemporaryMode()
        XCTAssertTrue(conversation.isTemporary)
        XCTAssertEqual(conversation.title, "Temporary Chat")
        XCTAssertEqual(conversation.id, id)

        conversation.toggleTemporaryMode()
        XCTAssertFalse(conversation.isTemporary)
        XCTAssertEqual(conversation.title, "New Chat")
        XCTAssertFalse(conversation.hasCustomTitle)
        XCTAssertEqual(conversation.id, id)
    }

    func testHasUserMessagesRequiresUserRole() throws {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let assistant = ChatMessage(role: .assistant, content: "Hello")
        assistant.conversation = conversation
        conversation.messages.append(assistant)
        XCTAssertFalse(conversation.hasUserMessages)

        let user = ChatMessage(role: .user, content: "Hi")
        user.conversation = conversation
        conversation.messages.append(user)
        XCTAssertTrue(conversation.hasUserMessages)
    }
}

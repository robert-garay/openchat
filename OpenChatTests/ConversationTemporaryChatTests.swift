import XCTest
import SwiftData
@testable import OpenChat

final class ConversationTemporaryChatTests: XCTestCase {
    func testNewConversationDefaultsToPersisted() throws {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        XCTAssertFalse(conversation.isTemporary)
        XCTAssertEqual(conversation.title, "New Chat")
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
}

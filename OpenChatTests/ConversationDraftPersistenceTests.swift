import XCTest
@testable import OpenChat

final class ConversationDraftPersistenceTests: XCTestCase {
    func testDraftMessageDefaultsToEmpty() {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        XCTAssertEqual(conversation.draftMessage, "")
        XCTAssertTrue(conversation.draftAttachments.isEmpty)
        XCTAssertNil(conversation.lastUsedWebSearchProviderID)
    }

    func testDraftMessageCanBeSet() {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        conversation.draftMessage = "Hello, world!"
        XCTAssertEqual(conversation.draftMessage, "Hello, world!")
    }

    func testDraftAttachmentsRoundTrip() {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let attachment = ChatImageAttachment(mimeType: "image/jpeg", data: Data("fake-image".utf8))
        conversation.draftAttachments = [attachment]

        XCTAssertEqual(conversation.draftAttachments.count, 1)
        XCTAssertEqual(conversation.draftAttachments.first?.mimeType, "image/jpeg")
        XCTAssertEqual(conversation.draftAttachments.first?.data, Data("fake-image".utf8))
        XCTAssertNotNil(conversation.draftAttachmentsData)
    }

    func testDraftAttachmentsEmptyClearsData() {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let attachment = ChatImageAttachment(mimeType: "image/jpeg", data: Data("fake-image".utf8))
        conversation.draftAttachments = [attachment]
        XCTAssertNotNil(conversation.draftAttachmentsData)

        conversation.draftAttachments = []
        XCTAssertNil(conversation.draftAttachmentsData)
        XCTAssertTrue(conversation.draftAttachments.isEmpty)
    }

    func testLastUsedWebSearchProviderIDPersists() {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        conversation.lastUsedWebSearchProviderID = "tavily"
        XCTAssertEqual(conversation.lastUsedWebSearchProviderID, "tavily")
    }
}

import XCTest
@testable import OpenChat

final class ChatMessageProviderTests: XCTestCase {
    func testAssistantMessageStoresGeneratingProvider() {
        let message = ChatMessage(
            role: .assistant,
            content: "Hello",
            providerID: "anthropic",
            modelID: "claude-sonnet-4"
        )

        XCTAssertEqual(message.providerID, "anthropic")
        XCTAssertEqual(message.modelID, "claude-sonnet-4")
    }

    func testUserMessageDefaultsProviderToNil() {
        let message = ChatMessage(role: .user, content: "Hi")

        XCTAssertNil(message.providerID)
        XCTAssertNil(message.modelID)
    }
}

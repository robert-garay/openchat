import XCTest
@testable import OpenChat

final class ChatRequestHistoryTests: XCTestCase {
    func testIncludeImagesKeepsAttachments() {
        let image = ChatImageAttachment(mimeType: "image/jpeg", data: Data([1, 2, 3]))
        let message = ChatMessage(role: .user, content: "What is this?", imageAttachments: [image])

        let turns = ChatRequestHistory.turns(from: [message], includeImages: true)

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].content, "What is this?")
        XCTAssertEqual(turns[0].images.count, 1)
        XCTAssertEqual(turns[0].images[0].data, Data([1, 2, 3]))
    }

    func testOmitImagesKeepsTextAndAddsPlaceholder() {
        let image = ChatImageAttachment(mimeType: "image/jpeg", data: Data([1, 2, 3]))
        let message = ChatMessage(role: .user, content: "What is this?", imageAttachments: [image])

        let turns = ChatRequestHistory.turns(from: [message], includeImages: false)

        XCTAssertEqual(turns.count, 1)
        XCTAssertTrue(turns[0].images.isEmpty)
        XCTAssertTrue(turns[0].content.contains("What is this?"))
        XCTAssertTrue(turns[0].content.contains(ChatRequestHistory.omittedImagePlaceholder))
    }

    func testOmitImagesReplacesImageOnlyTurnWithPlaceholder() {
        let image = ChatImageAttachment(mimeType: "image/png", data: Data([9]))
        let message = ChatMessage(role: .user, content: "", imageAttachments: [image])

        let turns = ChatRequestHistory.turns(from: [message], includeImages: false)

        XCTAssertEqual(turns.count, 1)
        XCTAssertTrue(turns[0].images.isEmpty)
        XCTAssertEqual(turns[0].content, ChatRequestHistory.omittedImagePlaceholder)
    }

    func testSwitchingIncludeImagesIsReversibleWithoutMutatingMessage() {
        let image = ChatImageAttachment(mimeType: "image/jpeg", data: Data([4, 5]))
        let message = ChatMessage(role: .user, content: "look", imageAttachments: [image])

        _ = ChatRequestHistory.turns(from: [message], includeImages: false)
        let restored = ChatRequestHistory.turns(from: [message], includeImages: true)

        XCTAssertEqual(message.imageAttachments.count, 1)
        XCTAssertEqual(restored[0].images.count, 1)
        XCTAssertEqual(restored[0].content, "look")
    }

    func testExcludingMessageID() {
        let keep = ChatMessage(role: .user, content: "hi")
        let drop = ChatMessage(role: .assistant, content: "", isStreaming: true)

        let turns = ChatRequestHistory.turns(
            from: [keep, drop],
            includeImages: true,
            excludingMessageID: drop.id
        )

        XCTAssertEqual(turns.map(\.content), ["hi"])
    }
}

import XCTest
@testable import OpenChat

final class ChatMessageImageAttachmentsTests: XCTestCase {
    func testAssigningImageAttachmentsReplacesExisting() {
        let original = ChatImageAttachment(mimeType: "image/png", data: Data([0x01]))
        let message = ChatMessage(role: .user, content: "Hi", imageAttachments: [original])

        let replacement = ChatImageAttachment(mimeType: "image/jpeg", data: Data([0x02]))
        message.imageAttachments = [replacement]

        XCTAssertEqual(message.imageAttachments, [replacement])
    }

    func testAssigningEmptyImageAttachmentsClearsAttachmentsData() {
        let attachment = ChatImageAttachment(mimeType: "image/png", data: Data([0x01]))
        let message = ChatMessage(role: .user, content: "Hi", imageAttachments: [attachment])
        XCTAssertNotNil(message.attachmentsData)

        message.imageAttachments = []

        XCTAssertNil(message.attachmentsData)
        XCTAssertEqual(message.imageAttachments, [])
    }
}

import XCTest
import UIKit
@testable import OpenChat

final class MultimodalAttachmentTests: XCTestCase {
    func testChatImageAttachmentRoundTrip() throws {
        let original = ChatImageAttachment(mimeType: "image/jpeg", data: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let encoded = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([ChatImageAttachment].self, from: encoded)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].mimeType, "image/jpeg")
        XCTAssertEqual(decoded[0].data, original.data)
        XCTAssertTrue(decoded[0].dataURI.hasPrefix("data:image/jpeg;base64,"))
    }

    func testImageAttachmentEncoderProducesJPEG() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        let attachment = ImageAttachmentEncoder.makeAttachment(from: image)
        XCTAssertNotNil(attachment)
        XCTAssertEqual(attachment?.mimeType, "image/jpeg")
        XCTAssertFalse(attachment?.data.isEmpty ?? true)
        XCTAssertNotNil(UIImage(data: attachment!.data))
    }

    func testOpenAIMultimodalPartsIncludeImageAndText() throws {
        let image = ChatImageAttachment(mimeType: "image/png", data: Data([1, 2, 3]))
        let turn = ChatTurn(role: .user, content: "What is this?", images: [image])
        let parts = MultimodalRequestEncoder.openAIParts(for: turn)
        XCTAssertEqual(parts?.count, 2)
        XCTAssertEqual(parts?[0].type, "image_url")
        XCTAssertEqual(parts?[0].imageURL?.url, image.dataURI)
        XCTAssertEqual(parts?[1].type, "text")
        XCTAssertEqual(parts?[1].text, "What is this?")

        let textOnly = MultimodalRequestEncoder.openAIParts(for: ChatTurn(role: .user, content: "hi"))
        XCTAssertNil(textOnly)
    }

    func testAnthropicMultimodalPartsIncludeImageAndText() {
        let image = ChatImageAttachment(mimeType: "image/jpeg", data: Data([9, 8, 7]))
        let turn = ChatTurn(role: .user, content: "Describe", images: [image])
        let parts = MultimodalRequestEncoder.anthropicParts(for: turn)
        XCTAssertEqual(parts?.count, 2)
        XCTAssertEqual(parts?[0].type, "image")
        XCTAssertEqual(parts?[0].source?.mediaType, "image/jpeg")
        XCTAssertEqual(parts?[0].source?.data, image.data.base64EncodedString())
        XCTAssertEqual(parts?[1].type, "text")
        XCTAssertEqual(parts?[1].text, "Describe")
    }

    func testVisionCapabilityErrorMessage() {
        let message = ChatServiceError.modelLacksVision.errorDescription
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("can") == true)
        XCTAssertTrue(message?.localizedCaseInsensitiveContains("images") == true)
        XCTAssertTrue(message?.localizedCaseInsensitiveContains("vision") == true)
    }

    func testChatMessageStoresAttachments() {
        let image = ChatImageAttachment(mimeType: "image/jpeg", data: Data([4, 5, 6]))
        let message = ChatMessage(role: .user, content: "look", imageAttachments: [image])
        XCTAssertEqual(message.imageAttachments.count, 1)
        XCTAssertEqual(message.imageAttachments[0].data, Data([4, 5, 6]))
        message.imageAttachments = []
        XCTAssertNil(message.attachmentsData)
    }
}

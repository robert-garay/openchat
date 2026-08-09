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

    func testGeneratedImageParserDataURI() {
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47])
        let uri = "data:image/png;base64,\(pngBytes.base64EncodedString())"
        let attachment = GeneratedImageParser.attachment(fromDataURI: uri)
        XCTAssertEqual(attachment?.mimeType, "image/png")
        XCTAssertEqual(attachment?.data, pngBytes)
        XCTAssertNil(GeneratedImageParser.attachment(fromDataURI: "https://example.com/x.png"))
    }

    func testGeneratedImageParserExtractsMarkdownDataURI() {
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        let uri = "data:image/png;base64,\(pngBytes.base64EncodedString())"
        let markdown = "Here you go:\n\n![generated](\(uri))\n\nEnjoy."
        let result = GeneratedImageParser.extractMarkdownDataURIImages(from: markdown)
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.images[0].data, pngBytes)
        XCTAssertFalse(result.text.contains("data:image"))
        XCTAssertTrue(result.text.contains("Here you go"))
        XCTAssertTrue(result.text.contains("Enjoy"))
    }

    func testAssistantMessageCanStoreGeneratedImages() {
        let image = ChatImageAttachment(mimeType: "image/png", data: Data([1, 2, 3, 4]))
        let message = ChatMessage(role: .assistant, content: "A cat", imageAttachments: [image])
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.imageAttachments.count, 1)
        XCTAssertEqual(message.content, "A cat")
    }

    func testGeneratedImageParserExtractsImageTagDataURI() {
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47])
        let uri = "data:image/png;base64,\(pngBytes.base64EncodedString())"
        let text = "Here:<image>\(uri)</image>Done."
        let result = GeneratedImageParser.extractImageTagDataURIs(from: text)
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.images[0].data, pngBytes)
        XCTAssertFalse(result.text.contains("<image"))
        XCTAssertTrue(result.text.contains("Here:"))
        XCTAssertTrue(result.text.contains("Done."))
    }

    func testGeneratedImageParserStripsPlaceholdersWhenImagesExist() {
        let text = "A <image> and {image} plus a sentence."
        let result = GeneratedImageParser.extractInlineImages(from: text, hasExistingImages: true)
        XCTAssertTrue(result.images.isEmpty)
        XCTAssertFalse(result.text.contains("<image"))
        XCTAssertFalse(result.text.contains("{image}"))
        XCTAssertTrue(result.text.contains("plus a sentence"))
    }

    func testGeneratedImageParserExtractsInlineImagesAndStripsPlaceholders() {
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47])
        let uri = "data:image/png;base64,\(pngBytes.base64EncodedString())"
        let text = "See this: {image}<image>\(uri)</image>Done."
        let result = GeneratedImageParser.extractInlineImages(from: text, hasExistingImages: false)
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.images[0].data, pngBytes)
        XCTAssertFalse(result.text.contains("{image}"))
        XCTAssertFalse(result.text.contains("<image"))
        XCTAssertTrue(result.text.contains("See this:"))
        XCTAssertTrue(result.text.contains("Done."))
    }
}

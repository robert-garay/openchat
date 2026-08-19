import XCTest
import UIKit
@testable import OpenChat

final class GeneratedImageDeduperTests: XCTestCase {
    func testUniqueDropsExactByteDuplicates() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        let first = ChatImageAttachment(mimeType: "image/png", data: bytes)
        let second = ChatImageAttachment(mimeType: "image/png", data: bytes)

        let unique = GeneratedImageDeduper.unique(from: [first, second])

        XCTAssertEqual(unique.count, 1)
        XCTAssertEqual(unique[0].id, first.id)
    }

    func testUniqueKeepsUndecodableImagesWithDifferentBytes() {
        let first = ChatImageAttachment(mimeType: "image/png", data: Data([0x01, 0x02]))
        let second = ChatImageAttachment(mimeType: "image/png", data: Data([0x03, 0x04]))

        let unique = GeneratedImageDeduper.unique(from: [first, second])

        XCTAssertEqual(unique.map(\.id), [first.id, second.id])
    }

    func testUniqueDropsSameDesignReencodedAsJPEG() throws {
        let image = patternedImage(primary: .red, secondary: .blue, corner: .topLeft)
        let png = try pngAttachment(image)
        let jpeg = try jpegAttachment(image)

        let unique = GeneratedImageDeduper.unique(from: [png, jpeg])

        XCTAssertEqual(unique.count, 1)
        XCTAssertEqual(unique[0].id, png.id)
    }

    func testUniqueKeepsDifferentDesigns() throws {
        let left = try pngAttachment(patternedImage(primary: .red, secondary: .blue, corner: .topLeft))
        let right = try pngAttachment(patternedImage(primary: .green, secondary: .yellow, corner: .bottomRight))

        let unique = GeneratedImageDeduper.unique(from: [left, right])

        XCTAssertEqual(unique.map(\.id), [left.id, right.id])
    }

    func testUniqueKeepsDifferentSolidColors() throws {
        let red = try pngAttachment(solidImage(.red))
        let blue = try pngAttachment(solidImage(.blue))

        let unique = GeneratedImageDeduper.unique(from: [red, blue])

        XCTAssertEqual(unique.map(\.id), [red.id, blue.id])
    }

    func testUniqueDropsNearDuplicateWithTinyPixelNoise() throws {
        let base = patternedImage(primary: .purple, secondary: .orange, corner: .topLeft)
        let noisy = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { _ in
            base.draw(in: CGRect(x: 0, y: 0, width: 64, height: 64))
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 63, y: 63, width: 1, height: 1))
        }
        let original = try pngAttachment(base)
        let perturbed = try pngAttachment(noisy)

        let unique = GeneratedImageDeduper.unique(from: [original, perturbed])

        XCTAssertEqual(unique.count, 1)
        XCTAssertEqual(unique[0].id, original.id)
    }

    func testUniqueLeavesEmptyAndSingleListsUnchanged() throws {
        XCTAssertTrue(GeneratedImageDeduper.unique(from: []).isEmpty)

        let only = try pngAttachment(solidImage(.cyan))
        let unique = GeneratedImageDeduper.unique(from: [only])
        XCTAssertEqual(unique.map(\.id), [only.id])
    }

    func testMergingDropsIncomingDuplicateOfExisting() throws {
        let image = patternedImage(primary: .red, secondary: .blue, corner: .topLeft)
        let existing = try pngAttachment(image)
        let incoming = try jpegAttachment(image)
        let extra = try pngAttachment(patternedImage(primary: .black, secondary: .white, corner: .bottomRight))

        let merged = GeneratedImageDeduper.merging([incoming, extra], into: [existing])

        XCTAssertEqual(merged.map(\.id), [existing.id, extra.id])
    }

    func testExtractInlineImagesDropsDuplicateTagAndMarkdownEmbeds() throws {
        let image = patternedImage(primary: .red, secondary: .blue, corner: .topLeft)
        let uri = try pngDataURI(image)
        let text = "See:<image>\(uri)</image>\n\n![generated](\(uri))\nDone."

        let result = GeneratedImageParser.extractInlineImages(from: text, hasExistingImages: false)

        XCTAssertEqual(result.images.count, 1)
        XCTAssertFalse(result.text.contains("data:image"))
        XCTAssertTrue(result.text.contains("See:"))
        XCTAssertTrue(result.text.contains("Done."))
    }

    func testExtractInlineImagesOnMessageDropsDuplicateOfExistingAttachment() throws {
        let image = patternedImage(primary: .red, secondary: .blue, corner: .topLeft)
        let pngData = try XCTUnwrap(image.pngData())
        let existing = ChatImageAttachment(mimeType: "image/png", data: pngData)
        let uri = "data:image/png;base64,\(pngData.base64EncodedString())"
        let message = ChatMessage(
            role: .assistant,
            content: "Here:<image>\(uri)</image>",
            imageAttachments: [existing]
        )

        message.extractInlineImages()

        XCTAssertEqual(message.imageAttachments.count, 1)
        XCTAssertEqual(message.imageAttachments[0].id, existing.id)
        XCTAssertFalse(message.content.contains("<image"))
    }

    func testExtractInlineImagesOnMessageKeepsADifferentDesign() throws {
        let existingImage = patternedImage(primary: .red, secondary: .blue, corner: .topLeft)
        let incomingImage = patternedImage(primary: .green, secondary: .yellow, corner: .bottomRight)
        let existing = try pngAttachment(existingImage)
        let uri = try pngDataURI(incomingImage)
        let message = ChatMessage(
            role: .assistant,
            content: "<image>\(uri)</image>",
            imageAttachments: [existing]
        )

        message.extractInlineImages()

        XCTAssertEqual(message.imageAttachments.count, 2)
        XCTAssertEqual(message.imageAttachments[0].id, existing.id)
    }
}

private extension GeneratedImageDeduperTests {
    enum PatternCorner {
        case topLeft
        case bottomRight
    }

    func solidImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
    }

    func patternedImage(primary: UIColor, secondary: UIColor, corner: PatternCorner) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            primary.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            secondary.setFill()
            let block: CGRect = switch corner {
            case .topLeft:
                CGRect(x: 4, y: 4, width: 28, height: 28)
            case .bottomRight:
                CGRect(x: 32, y: 32, width: 28, height: 28)
            }
            context.fill(block)
        }
    }

    func pngAttachment(_ image: UIImage) throws -> ChatImageAttachment {
        ChatImageAttachment(mimeType: "image/png", data: try XCTUnwrap(image.pngData()))
    }

    func jpegAttachment(_ image: UIImage) throws -> ChatImageAttachment {
        ChatImageAttachment(mimeType: "image/jpeg", data: try XCTUnwrap(image.jpegData(compressionQuality: 0.8)))
    }

    func pngDataURI(_ image: UIImage) throws -> String {
        let data = try XCTUnwrap(image.pngData())
        return "data:image/png;base64,\(data.base64EncodedString())"
    }
}

import CoreGraphics
import XCTest
@testable import OpenChat

final class ImageGalleryTests: XCTestCase {
    func testAttachmentsCollectsImagesInChronologicalMessageOrder() {
        let first = ChatImageAttachment(mimeType: "image/png", data: Data([0x01]))
        let second = ChatImageAttachment(mimeType: "image/png", data: Data([0x02]))
        let third = ChatImageAttachment(mimeType: "image/png", data: Data([0x03]))

        let later = ChatMessage(
            role: .assistant,
            content: "here",
            createdAt: Date(timeIntervalSince1970: 20),
            imageAttachments: [second, third]
        )
        let earlier = ChatMessage(
            role: .user,
            content: "look",
            createdAt: Date(timeIntervalSince1970: 10),
            imageAttachments: [first]
        )
        let textOnly = ChatMessage(
            role: .assistant,
            content: "ok",
            createdAt: Date(timeIntervalSince1970: 15)
        )

        let attachments = ImageGallery.attachments(in: [later, earlier, textOnly])

        XCTAssertEqual(attachments.map(\.id), [first.id, second.id, third.id])
    }

    func testInitSelectsMatchingAttachment() {
        let first = ChatImageAttachment(mimeType: "image/png", data: Data([0x01]))
        let second = ChatImageAttachment(mimeType: "image/png", data: Data([0x02]))

        let gallery = ImageGallery(attachments: [first, second], selectedID: second.id)

        XCTAssertEqual(gallery.selectedIndex, 1)
        XCTAssertEqual(gallery.selectedAttachment?.id, second.id)
        XCTAssertTrue(gallery.canGoPrevious)
        XCTAssertFalse(gallery.canGoNext)
    }

    func testInitFallsBackToFirstWhenSelectedIDIsMissing() {
        let first = ChatImageAttachment(mimeType: "image/png", data: Data([0x01]))
        let gallery = ImageGallery(attachments: [first], selectedID: UUID())

        XCTAssertEqual(gallery.selectedIndex, 0)
        XCTAssertEqual(gallery.selectedAttachment?.id, first.id)
    }

    func testEmptyGalleryCannotNavigate() {
        let gallery = ImageGallery(attachments: [], selectedID: UUID())

        XCTAssertEqual(gallery.selectedIndex, 0)
        XCTAssertNil(gallery.selectedAttachment)
        XCTAssertFalse(gallery.canGoPrevious)
        XCTAssertFalse(gallery.canGoNext)
        XCTAssertTrue(gallery.attachments.isEmpty)
    }

    func testSingleImageCannotNavigate() {
        let image = ChatImageAttachment(mimeType: "image/png", data: Data([0x01]))
        var gallery = ImageGallery(attachments: [image], selectedID: image.id)

        XCTAssertFalse(gallery.canGoPrevious)
        XCTAssertFalse(gallery.canGoNext)

        gallery.selectNext()
        gallery.selectPrevious()

        XCTAssertEqual(gallery.selectedIndex, 0)
        XCTAssertEqual(gallery.selectedAttachment?.id, image.id)
    }

    func testSelectNextAdvancesUntilTheLastImage() {
        let images = [
            ChatImageAttachment(mimeType: "image/png", data: Data([0x01])),
            ChatImageAttachment(mimeType: "image/png", data: Data([0x02])),
            ChatImageAttachment(mimeType: "image/png", data: Data([0x03]))
        ]
        var gallery = ImageGallery(attachments: images, selectedID: images[0].id)

        XCTAssertTrue(gallery.canGoNext)
        gallery.selectNext()
        XCTAssertEqual(gallery.selectedIndex, 1)
        XCTAssertTrue(gallery.canGoPrevious)
        XCTAssertTrue(gallery.canGoNext)

        gallery.selectNext()
        XCTAssertEqual(gallery.selectedIndex, 2)
        XCTAssertFalse(gallery.canGoNext)

        gallery.selectNext()
        XCTAssertEqual(gallery.selectedIndex, 2)
    }

    func testSelectPreviousRetreatsUntilTheFirstImage() {
        let images = [
            ChatImageAttachment(mimeType: "image/png", data: Data([0x01])),
            ChatImageAttachment(mimeType: "image/png", data: Data([0x02])),
            ChatImageAttachment(mimeType: "image/png", data: Data([0x03]))
        ]
        var gallery = ImageGallery(attachments: images, selectedID: images[2].id)

        gallery.selectPrevious()
        XCTAssertEqual(gallery.selectedIndex, 1)
        gallery.selectPrevious()
        XCTAssertEqual(gallery.selectedIndex, 0)
        XCTAssertFalse(gallery.canGoPrevious)

        gallery.selectPrevious()
        XCTAssertEqual(gallery.selectedIndex, 0)
    }
}

final class ImagePreviewDismissPolicyTests: XCTestCase {
    func testDismissesWhenDraggedDownPastDistanceThreshold() {
        XCTAssertTrue(
            ImagePreviewDismissPolicy.shouldDismiss(
                translation: CGSize(width: 10, height: 160),
                predictedEndTranslation: CGSize(width: 10, height: 180)
            )
        )
    }

    func testDoesNotDismissOnAShortDownwardDrag() {
        XCTAssertFalse(
            ImagePreviewDismissPolicy.shouldDismiss(
                translation: CGSize(width: 4, height: 40),
                predictedEndTranslation: CGSize(width: 6, height: 70)
            )
        )
    }

    func testDoesNotDismissWhenTheDragIsMostlyHorizontal() {
        XCTAssertFalse(
            ImagePreviewDismissPolicy.shouldDismiss(
                translation: CGSize(width: 200, height: 160),
                predictedEndTranslation: CGSize(width: 280, height: 180)
            )
        )
    }

    func testDoesNotDismissWhenDraggedUp() {
        XCTAssertFalse(
            ImagePreviewDismissPolicy.shouldDismiss(
                translation: CGSize(width: 0, height: -180),
                predictedEndTranslation: CGSize(width: 0, height: -260)
            )
        )
    }

    func testDismissesOnADownwardFlick() {
        XCTAssertTrue(
            ImagePreviewDismissPolicy.shouldDismiss(
                translation: CGSize(width: 8, height: 50),
                predictedEndTranslation: CGSize(width: 10, height: 320)
            )
        )
    }
}

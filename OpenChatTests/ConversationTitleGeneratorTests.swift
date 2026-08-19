import XCTest
@testable import OpenChat

final class ConversationTitleGeneratorTests: XCTestCase {
    func testFallbackUsesFirstLineAndWordBoundary() {
        let title = ConversationTitleGenerator.fallbackTitle(
            for: "How do I sort a list in Python efficiently?\nWith many items",
            hasImages: false
        )
        XCTAssertEqual(title, "How do I sort a list in Python")
        XCTAssertLessThanOrEqual(title.count, 40)
    }

    func testFallbackForImageOnlyMessage() {
        XCTAssertEqual(
            ConversationTitleGenerator.fallbackTitle(for: "  ", hasImages: true),
            "Image"
        )
    }

    func testSanitizeStripsQuotesAndPunctuation() {
        XCTAssertEqual(
            ConversationTitleGenerator.sanitize("  \"Python Sorting Tips\".  "),
            "Python Sorting Tips"
        )
    }

    func testSanitizeTakesFirstLineAndDropsTitlePrefix() {
        XCTAssertEqual(
            ConversationTitleGenerator.sanitize("Title: Weekend Hiking Plans\nExtra noise"),
            "Weekend Hiking Plans"
        )
    }

    func testSanitizeRejectsEmpty() {
        XCTAssertNil(ConversationTitleGenerator.sanitize("   \"\"  "))
    }

    func testSanitizeStripsBoldAsterisks() {
        XCTAssertEqual(
            ConversationTitleGenerator.sanitize("**Trip Planning**"),
            "Trip Planning"
        )
    }

    func testSanitizeStripsLeadingHeadingMarker() {
        XCTAssertEqual(
            ConversationTitleGenerator.sanitize("# Weekend Getaway"),
            "Weekend Getaway"
        )
    }

    func testSanitizeStripsInlineCodeBackticks() {
        XCTAssertEqual(
            ConversationTitleGenerator.sanitize("`inline code` title"),
            "inline code title"
        )
    }

    func testSanitizeStripsUnderscoreEmphasis() {
        XCTAssertEqual(
            ConversationTitleGenerator.sanitize("_Quarterly Review_"),
            "Quarterly Review"
        )
    }
}

final class ConversationRenameTests: XCTestCase {
    func testRenameLocksCustomTitle() {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        XCTAssertTrue(conversation.needsAutoTitle)

        conversation.rename(to: "  My Project  ")
        XCTAssertEqual(conversation.title, "My Project")
        XCTAssertTrue(conversation.hasCustomTitle)
        XCTAssertFalse(conversation.needsAutoTitle)
    }

    func testRenameIgnoresBlank() {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        conversation.rename(to: "   ")
        XCTAssertEqual(conversation.title, "New Chat")
        XCTAssertFalse(conversation.hasCustomTitle)
    }

    func testToggleTemporaryClearsCustomTitle() {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        conversation.rename(to: "Keep Me")
        conversation.toggleTemporaryMode()
        XCTAssertTrue(conversation.isTemporary)
        XCTAssertEqual(conversation.title, "Temporary Chat")
        XCTAssertFalse(conversation.hasCustomTitle)
    }

    func testTogglePinnedFlipsFlag() {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        XCTAssertFalse(conversation.isPinned)
        conversation.togglePinned()
        XCTAssertTrue(conversation.isPinned)
        conversation.togglePinned()
        XCTAssertFalse(conversation.isPinned)
    }
}

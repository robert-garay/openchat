import XCTest
@testable import OpenChat

final class ConversationCompactionTests: XCTestCase {
    private func makeSnapshot(
        id: UUID = UUID(),
        role: MessageRole = .user,
        content: String,
        imageCount: Int = 0
    ) -> CompactionMessageSnapshot {
        CompactionMessageSnapshot(
            id: id,
            role: role,
            content: content,
            imageCount: imageCount,
            createdAt: .now
        )
    }

    private func makeMessage(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        images: [ChatImageAttachment] = []
    ) -> ChatMessage {
        ChatMessage(id: id, role: role, content: content, imageAttachments: images)
    }

    func testSettingsDefaultOff() {
        let defaults = UserDefaults(suiteName: "com.openchat.tests.compact.\(UUID().uuidString)")!
        XCTAssertFalse(CompactConversationSettings.isEnabled(defaults: defaults))
        XCTAssertNil(defaults.object(forKey: CompactConversationSettings.enabledKey))
    }

    func testConversationCompactionFieldsDefaultEmpty() {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        XCTAssertEqual(conversation.compactedSummary, "")
        XCTAssertNil(conversation.compactedThroughMessageID)
    }

    func testPlanCompactionRequiresMinimumMessages() {
        let messages = (1...9).map { makeSnapshot(content: "Message \($0)") }
        XCTAssertNil(
            ConversationCompactionService.planCompaction(
                sortedMessages: messages,
                compactedThroughMessageID: nil
            )
        )
        XCTAssertFalse(ConversationCompactionService.canCompact(messageCount: 9))
        XCTAssertTrue(ConversationCompactionService.canCompact(messageCount: 10))
    }

    func testPlanCompactionKeepsRecentMessages() {
        let messages = (1...12).map { makeSnapshot(content: "Message \($0)") }
        let plan = ConversationCompactionService.planCompaction(
            sortedMessages: messages,
            compactedThroughMessageID: nil
        )

        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.messagesToSummarize.count, 4)
        XCTAssertEqual(plan?.recentMessages.count, 8)
        XCTAssertEqual(plan?.messagesToSummarize.map(\.content), ["Message 1", "Message 2", "Message 3", "Message 4"])
        XCTAssertEqual(plan?.recentMessages.first?.content, "Message 5")
        XCTAssertEqual(plan?.recentMessages.last?.content, "Message 12")
        XCTAssertEqual(plan?.watermarkMessageID, messages[3].id)
    }

    func testPlanCompactionRespectsExistingWatermark() {
        let ids = (0..<15).map { _ in UUID() }
        let messages = ids.enumerated().map { index, id in
            makeSnapshot(id: id, content: "Message \(index + 1)")
        }

        let firstPlan = ConversationCompactionService.planCompaction(
            sortedMessages: messages,
            compactedThroughMessageID: nil
        )
        XCTAssertEqual(firstPlan?.messagesToSummarize.count, 7)

        let secondPlan = ConversationCompactionService.planCompaction(
            sortedMessages: messages,
            compactedThroughMessageID: firstPlan?.watermarkMessageID
        )
        XCTAssertNil(secondPlan)

        let extended = messages + (16...20).map { makeSnapshot(content: "Message \($0)") }
        let thirdPlan = ConversationCompactionService.planCompaction(
            sortedMessages: extended,
            compactedThroughMessageID: firstPlan?.watermarkMessageID
        )
        XCTAssertEqual(thirdPlan?.messagesToSummarize.count, 5)
        XCTAssertEqual(thirdPlan?.watermarkMessageID, extended[11].id)
    }

    func testSummarizationLineNotesImages() {
        let snapshot = makeSnapshot(role: .user, content: "Look at this", imageCount: 2)
        let line = ConversationCompactionService.lineForSummarization(snapshot)
        XCTAssertTrue(line.contains("[shared 2 images]"))
    }

    func testAPIHistoryTurnsWithoutCompactionIncludesAllMessages() {
        let user = makeMessage(role: .user, content: "Hi")
        let assistant = makeMessage(role: .assistant, content: "Hello")
        let turns = ConversationCompactionService.apiHistoryTurns(
            sortedMessages: [user, assistant],
            compactedSummary: nil,
            compactedThroughMessageID: nil
        )

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].content, "Hi")
        XCTAssertEqual(turns[1].content, "Hello")
    }

    func testAPIHistoryTurnsInjectsSummaryAndPostWatermarkOnly() {
        let ids = (0..<5).map { _ in UUID() }
        let messages = [
            makeMessage(id: ids[0], role: .user, content: "Old 1"),
            makeMessage(id: ids[1], role: .assistant, content: "Old 2"),
            makeMessage(id: ids[2], role: .user, content: "Recent 1"),
            makeMessage(id: ids[3], role: .assistant, content: "Recent 2"),
            makeMessage(id: ids[4], role: .user, content: "Recent 3")
        ]

        let turns = ConversationCompactionService.apiHistoryTurns(
            sortedMessages: messages,
            compactedSummary: "Earlier discussion about testing.",
            compactedThroughMessageID: ids[1],
            excludingMessageID: nil
        )

        XCTAssertEqual(turns.count, 4)
        XCTAssertTrue(turns[0].content.contains("[Compacted conversation context]"))
        XCTAssertTrue(turns[0].content.contains("Earlier discussion"))
        XCTAssertEqual(turns[1].content, "Recent 1")
        XCTAssertEqual(turns[2].content, "Recent 2")
        XCTAssertEqual(turns[3].content, "Recent 3")
        XCTAssertTrue(turns.allSatisfy { $0.images.isEmpty })
    }

    func testAPIHistoryTurnsOmitsCompactedImageBinaries() {
        let attachment = ChatImageAttachment(mimeType: "image/jpeg", data: Data([0xFF, 0xD8, 0xFF]))
        let old = makeMessage(id: UUID(), role: .user, content: "Photo", images: [attachment])
        let recent = makeMessage(role: .user, content: "Follow up")

        let turns = ConversationCompactionService.apiHistoryTurns(
            sortedMessages: [old, recent],
            compactedSummary: "User shared a photo.",
            compactedThroughMessageID: old.id
        )

        XCTAssertEqual(turns.count, 2)
        XCTAssertTrue(turns[0].content.contains("Compacted conversation context"))
        XCTAssertEqual(turns[1].content, "Follow up")
        XCTAssertTrue(turns[1].images.isEmpty)
    }

    func testAPIHistoryTurnsOmitsCompactedDocumentBinariesWhenExcluded() {
        let document = ChatDocumentAttachment(filename: "report.pdf", mimeType: "application/pdf", data: Data([0x25, 0x50, 0x44, 0x46]))
        let old = ChatMessage(role: .user, content: "Doc", documentAttachments: [document])
        let recent = ChatMessage(role: .user, content: "Follow up")

        let turns = ConversationCompactionService.apiHistoryTurns(
            sortedMessages: [old, recent],
            compactedSummary: "User shared a document.",
            compactedThroughMessageID: old.id
        )

        XCTAssertEqual(turns.count, 2)
        XCTAssertTrue(turns[0].content.contains("Compacted conversation context"))
        XCTAssertEqual(turns[1].content, "Follow up")
        XCTAssertTrue(turns[1].documents.isEmpty)
    }

    func testAPIHistoryTurnsDocumentOnlyMessageEligibleForCompaction() {
        let document = ChatDocumentAttachment(filename: "report.pdf", mimeType: "application/pdf", data: Data([0x25, 0x50, 0x44, 0x46]))
        let documentOnly = ChatMessage(role: .user, content: "", documentAttachments: [document])
        let turns = ConversationCompactionService.apiHistoryTurns(
            sortedMessages: [documentOnly],
            compactedSummary: nil,
            compactedThroughMessageID: nil
        )
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].documents.count, 1)
    }
}

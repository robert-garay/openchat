import Testing
@testable import OpenChat

struct ContinuationTurnsTests {
    @Test("appends the partial reply and a continue instruction after the original turns")
    func appendsPartialReplyAndContinueInstruction() {
        let original = [ChatTurn(role: .user, content: "Tell me a story")]
        let turns = BackgroundGenerationService.continuationTurns(
            previousTurns: original,
            partialContent: "Once upon a time,"
        )

        #expect(turns.count == 3)
        #expect(turns[0].role == .user)
        #expect(turns[0].content == "Tell me a story")
        #expect(turns[1].role == .assistant)
        #expect(turns[1].content == "Once upon a time,")
        #expect(turns[2].role == .user)
        #expect(turns[2].content.localizedCaseInsensitiveContains("continue"))
    }
}

import XCTest
@testable import OpenChat

/// Feature gating (useGlobalRules / useChatRules) happens at the ChatViewModel call site
/// before values are passed into `assemble`.
final class ChatSystemPromptBuilderTests: XCTestCase {
    func testAssemblesToolsGlobalMiddleAndChatRulesInOrder() {
        let result = ChatSystemPromptBuilder.assemble(
            globalRules: "Global rule",
            chatRules: "Chat rule",
            middleSections: ["Agent context"],
            webSearchToolPrompt: "Tool prompt"
        )

        XCTAssertEqual(
            result,
            "Tool prompt\n\nGlobal rule\n\nAgent context\n\nChat rules:\nChat rule"
        )
    }

    func testChatRulesAppearAfterGlobalRules() {
        let result = ChatSystemPromptBuilder.assemble(
            globalRules: "Use metric units.",
            chatRules: "Use imperial units.",
            middleSections: [],
            webSearchToolPrompt: nil
        )

        XCTAssertEqual(result, "Use metric units.\n\nChat rules:\nUse imperial units.")
    }

    func testEmptyInputsReturnNil() {
        XCTAssertNil(
            ChatSystemPromptBuilder.assemble(
                globalRules: "",
                chatRules: "",
                middleSections: [],
                webSearchToolPrompt: nil
            )
        )
    }

    func testMiddleSectionsPreserveOrderAfterGlobalRules() {
        let result = ChatSystemPromptBuilder.assemble(
            globalRules: "Global",
            chatRules: "Chat",
            middleSections: ["Skills block", "Injected search"],
            webSearchToolPrompt: "Tools"
        )

        let parts = result?.components(separatedBy: "\n\n") ?? []
        XCTAssertEqual(parts, ["Tools", "Global", "Skills block", "Injected search", "Chat rules:\nChat"])
    }
}

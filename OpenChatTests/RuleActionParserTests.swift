import XCTest
@testable import OpenChat

final class RuleActionParserTests: XCTestCase {
    func testParsesFenceSingleObject() {
        let proposals = RuleActionParser.parse(
            "```openchat-rule\n{\"content\":\"Always answer in Spanish.\",\"scope\":\"chat\"}\n```"
        )
        XCTAssertEqual(proposals.map(\.content), ["Always answer in Spanish."])
        XCTAssertEqual(proposals.map(\.scope), [.chat])
    }

    func testParsesTag() {
        let proposals = RuleActionParser.parse(
            "<rule_proposal>{\"content\":\"Be concise.\",\"scope\":\"global\"}</rule_proposal>"
        )
        XCTAssertEqual(proposals.map(\.content), ["Be concise."])
        XCTAssertEqual(proposals.map(\.scope), [.global])
    }

    func testParsesRulesArray() {
        let json = """
        {"rules":[{"content":"Use metric units.","scope":"global"},{"content":"Reply briefly.","scope":"chat"}]}
        """
        let proposals = RuleActionParser.parse("```openchat-rule\n\(json)\n```")
        XCTAssertEqual(proposals.map(\.content), ["Use metric units.", "Reply briefly."])
        XCTAssertEqual(proposals.map(\.scope), [.global, .chat])
    }

    func testDropsBlockMissingScope() {
        let proposals = RuleActionParser.parse("```openchat-rule\n{\"content\":\"No scope here.\"}\n```")
        XCTAssertTrue(proposals.isEmpty)
    }

    func testDropsBlockWithInvalidScope() {
        let proposals = RuleActionParser.parse(
            "```openchat-rule\n{\"content\":\"Bad scope.\",\"scope\":\"everywhere\"}\n```"
        )
        XCTAssertTrue(proposals.isEmpty)
    }

    func testDropsMalformedJSON() {
        let proposals = RuleActionParser.parse("```openchat-rule\nnot json\n```")
        XCTAssertTrue(proposals.isEmpty)
    }

    func testDropsEmptyContent() {
        let proposals = RuleActionParser.parse("```openchat-rule\n{\"content\":\"   \",\"scope\":\"chat\"}\n```")
        XCTAssertTrue(proposals.isEmpty)
    }

    func testDedupesByNormalizedContentKeepingFirst() {
        let markdown = """
        ```openchat-rule
        {"content":"Be concise.","scope":"chat"}
        ```
        <rule_proposal>{"content":"  be   CONCISE. ","scope":"global"}</rule_proposal>
        """
        let proposals = RuleActionParser.parse(markdown)
        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals.first?.scope, .chat)
    }

    func testStrippingFencesRemovesBothConventions() {
        let markdown = """
        Before
        ```openchat-rule
        {"content":"x","scope":"chat"}
        ```
        <rule_proposal>{"content":"y","scope":"global"}</rule_proposal>
        After
        """
        let stripped = RuleActionParser.strippingFences(from: markdown)
        XCTAssertFalse(stripped.contains("openchat-rule"))
        XCTAssertFalse(stripped.contains("rule_proposal"))
        XCTAssertTrue(stripped.hasPrefix("Before"))
        XCTAssertTrue(stripped.hasSuffix("After"))
    }
}

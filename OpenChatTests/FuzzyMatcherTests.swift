import XCTest
@testable import OpenChat

final class FuzzyMatcherTests: XCTestCase {
    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(FuzzyMatcher.matches(query: "", fields: ["gpt-5-nano"]))
        XCTAssertTrue(FuzzyMatcher.matches(query: "   ", fields: ["gpt-5-nano"]))
    }

    func testExactSubstringMatch() {
        XCTAssertTrue(FuzzyMatcher.matches(query: "5-nano", fields: ["openai/gpt-5-nano"]))
        XCTAssertTrue(FuzzyMatcher.matches(query: "gpt-5", fields: ["openai/gpt-5-nano"]))
    }

    func testTokenMatchAcrossSeparators() {
        XCTAssertTrue(FuzzyMatcher.matches(query: "gpt nano", fields: ["openai/gpt-5-nano"]))
        XCTAssertTrue(FuzzyMatcher.matches(query: "openai nano", fields: ["openai/gpt-5-nano"]))
    }

    func testStrippedSeparatorMatch() {
        XCTAssertTrue(FuzzyMatcher.matches(query: "gpt5nano", fields: ["openai/gpt-5-nano"]))
        XCTAssertTrue(FuzzyMatcher.matches(query: "5nano", fields: ["openai/gpt-5-nano"]))
    }

    func testAllQueryTokensMustMatch() {
        XCTAssertFalse(FuzzyMatcher.matches(query: "gpt claude", fields: ["openai/gpt-5-nano"]))
        XCTAssertTrue(FuzzyMatcher.matches(query: "gpt claude", fields: ["openai/gpt-5-nano", "anthropic/claude-sonnet"]))
    }

    func testMatchesAnyField() {
        XCTAssertTrue(FuzzyMatcher.matches(query: "openai", fields: ["gpt-5-nano", "OpenAI"]))
        XCTAssertTrue(FuzzyMatcher.matches(query: "sonnet", fields: ["anthropic/claude-sonnet-4.6", "Anthropic"]))
    }

    func testCaseInsensitiveMatch() {
        XCTAssertTrue(FuzzyMatcher.matches(query: "GPT NANO", fields: ["openai/gpt-5-nano"]))
        XCTAssertTrue(FuzzyMatcher.matches(query: "OpenAI", fields: ["OPENAI/gpt-5-nano"]))
    }
}

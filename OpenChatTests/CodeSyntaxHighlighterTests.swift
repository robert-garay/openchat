import XCTest
@testable import OpenChat

final class CodeSyntaxHighlighterTests: XCTestCase {
    func testResolvesLanguageAliases() {
        XCTAssertEqual(LanguageProfile.normalize("Swift"), "swift")
        XCTAssertEqual(LanguageProfile.profile(for: "py").keywords, LanguageProfile.python.keywords)
        XCTAssertEqual(LanguageProfile.profile(for: "js").keywords, LanguageProfile.javaScriptFamily.keywords)
        XCTAssertEqual(LanguageProfile.profile(for: "TSX").keywords, LanguageProfile.javaScriptFamily.keywords)
        XCTAssertEqual(LanguageProfile.profile(for: "yml").keywords, LanguageProfile.yaml.keywords)
    }

    func testSwiftHighlightsKeywordsStringsCommentsAndNumbers() {
        let code = """
        // setup
        let name = "Ada"
        func greet() -> Int { 42 }
        """
        let tokens = CodeSyntaxHighlighter.tokens(code: code, language: "swift")
        XCTAssertTrue(tokens.contains { $0.text == "let" && $0.kind == .keyword })
        XCTAssertTrue(tokens.contains { $0.text == "func" && $0.kind == .keyword })
        XCTAssertTrue(tokens.contains { $0.text == "\"Ada\"" && $0.kind == .string })
        XCTAssertTrue(tokens.contains { $0.text == "// setup" && $0.kind == .comment })
        XCTAssertTrue(tokens.contains { $0.text == "42" && $0.kind == .number })
        XCTAssertTrue(tokens.contains { $0.text == "Int" && $0.kind == .typeName })
    }

    func testSQLKeywordsAreCaseInsensitive() {
        let tokens = CodeSyntaxHighlighter.tokens(
            code: "select * FROM users WHERE id = 1",
            language: "sql"
        )
        XCTAssertTrue(tokens.contains { $0.text == "select" && $0.kind == .keyword })
        XCTAssertTrue(tokens.contains { $0.text == "FROM" && $0.kind == .keyword })
        XCTAssertTrue(tokens.contains { $0.text == "WHERE" && $0.kind == .keyword })
    }

    func testDoesNotColorKeywordsInsideStrings() {
        let code = #"let text = "func return class""#
        let tokens = CodeSyntaxHighlighter.tokens(code: code, language: "swift")
        XCTAssertTrue(tokens.contains { $0.text == "let" && $0.kind == .keyword })
        XCTAssertTrue(tokens.contains { $0.text == #""func return class""# && $0.kind == .string })
        XCTAssertFalse(tokens.contains { $0.text == "func" && $0.kind == .keyword })
        XCTAssertFalse(tokens.contains { $0.text == "return" && $0.kind == .keyword })
    }

    func testUnknownLanguageStillHighlightsStringsAndComments() {
        let tokens = CodeSyntaxHighlighter.tokens(
            code: """
            # note
            value = "hello"
            """,
            language: "obscurelang"
        )
        XCTAssertTrue(tokens.contains { $0.text == "# note" && $0.kind == .comment })
        XCTAssertTrue(tokens.contains { $0.text == "\"hello\"" && $0.kind == .string })
    }

    func testHighlightPreservesSourceText() {
        let code = "const x = 1; // ok"
        let attributed = CodeSyntaxHighlighter.highlight(code: code, language: "javascript")
        XCTAssertEqual(String(attributed.characters), code)
    }
}

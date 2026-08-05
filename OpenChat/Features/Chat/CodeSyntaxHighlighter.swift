import SwiftUI
import UIKit

/// Lightweight language-aware highlighter for fenced code blocks.
/// Covers the languages LLMs emit most often; unknown languages still get
/// string / comment / number coloring via a generic profile.
enum CodeSyntaxHighlighter {
    enum TokenKind: Equatable {
        case plain
        case keyword
        case typeName
        case string
        case comment
        case number
    }

    static func highlight(code: String, language: String?) -> AttributedString {
        let profile = LanguageProfile.profile(for: language)
        let spans = tokenize(code, profile: profile)
        var attributed = AttributedString(code)
        let baseFont = Font.system(.footnote, design: .monospaced)
        attributed.font = baseFont
        attributed.foregroundColor = Palette.plain

        for span in spans where span.kind != .plain {
            guard let range = Range(span.range, in: attributed) else { continue }
            attributed[range].foregroundColor = Palette.color(for: span.kind)
            attributed[range].font = baseFont
        }
        return attributed
    }

    /// Test/helper surface: returns non-plain tokens with their matched text.
    static func tokens(code: String, language: String?) -> [(text: String, kind: TokenKind)] {
        let profile = LanguageProfile.profile(for: language)
        let ns = code as NSString
        return tokenize(code, profile: profile).map { span in
            (ns.substring(with: span.range), span.kind)
        }
    }

    // MARK: - Regex Cache

    private static let regexCacheLock = NSLock()
    private static var regexCache: [String: NSRegularExpression] = [:]

    private static func cachedRegex(pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        let key = "\(pattern)|\(options.rawValue)"
        regexCacheLock.lock()
        defer { regexCacheLock.unlock() }
        if let cached = regexCache[key] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        regexCache[key] = regex
        return regex
    }

    // MARK: - Tokenization

    private struct Span {
        let range: NSRange
        let kind: TokenKind
    }

    private static func tokenize(_ code: String, profile: LanguageProfile) -> [Span] {
        let ns = code as NSString
        let full = NSRange(location: 0, length: ns.length)
        var occupied = Array(repeating: false, count: ns.length)
        var spans: [Span] = []

        func claim(_ range: NSRange, as kind: TokenKind) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            let end = range.location + range.length
            guard range.location < occupied.count, end <= occupied.count else { return }
            if occupied[range.location..<end].contains(true) { return }
            for i in range.location..<end { occupied[i] = true }
            spans.append(Span(range: range, kind: kind))
        }

        // Comments first so keywords inside them stay muted.
        if let pattern = profile.blockCommentPattern,
           let regex = cachedRegex(pattern: pattern) {
            for match in regex.matches(in: code, range: full) {
                claim(match.range, as: .comment)
            }
        }
        if let pattern = profile.lineCommentPattern,
           let regex = cachedRegex(pattern: pattern) {
            for match in regex.matches(in: code, range: full) {
                claim(match.range, as: .comment)
            }
        }

        for pattern in profile.stringPatterns {
            guard let regex = cachedRegex(pattern: pattern) else { continue }
            for match in regex.matches(in: code, range: full) {
                claim(match.range, as: .string)
            }
        }

        if let regex = cachedRegex(pattern: #"\b\d+(\.\d+)?([eE][+-]?\d+)?\b"#) {
            for match in regex.matches(in: code, range: full) {
                claim(match.range, as: .number)
            }
        }

        if !profile.keywords.isEmpty {
            let alternation = profile.keywords
                .sorted { $0.count > $1.count }
                .map(NSRegularExpression.escapedPattern(for:))
                .joined(separator: "|")
            let options: NSRegularExpression.Options = profile.caseInsensitiveKeywords ? .caseInsensitive : []
            if let regex = cachedRegex(pattern: "\\b(?:\(alternation))\\b", options: options) {
                for match in regex.matches(in: code, range: full) {
                    claim(match.range, as: .keyword)
                }
            }
        }

        if !profile.typeNames.isEmpty {
            let alternation = profile.typeNames
                .sorted { $0.count > $1.count }
                .map(NSRegularExpression.escapedPattern(for:))
                .joined(separator: "|")
            let options: NSRegularExpression.Options = profile.caseInsensitiveKeywords ? .caseInsensitive : []
            if let regex = cachedRegex(pattern: "\\b(?:\(alternation))\\b", options: options) {
                for match in regex.matches(in: code, range: full) {
                    claim(match.range, as: .typeName)
                }
            }
        }

        // Capitalized identifiers often denote types in Swift/Kotlin/Java/Go/Rust.
        if profile.highlightCapitalizedTypes,
           let regex = cachedRegex(pattern: #"\b[A-Z][A-Za-z0-9_]+\b"#) {
            for match in regex.matches(in: code, range: full) {
                claim(match.range, as: .typeName)
            }
        }

        return spans
    }
}

// MARK: - Palette

private enum Palette {
    static let plain = Color.primary.opacity(0.92)

    static func color(for kind: CodeSyntaxHighlighter.TokenKind) -> Color {
        switch kind {
        case .plain:
            return plain
        case .keyword:
            return dynamic(light: (0.55, 0.12, 0.58), dark: (0.95, 0.55, 0.78))
        case .typeName:
            return dynamic(light: (0.10, 0.45, 0.55), dark: (0.45, 0.85, 0.90))
        case .string:
            return dynamic(light: (0.72, 0.18, 0.18), dark: (0.95, 0.55, 0.45))
        case .comment:
            return dynamic(light: (0.28, 0.52, 0.28), dark: (0.48, 0.72, 0.48))
        case .number:
            return dynamic(light: (0.15, 0.30, 0.70), dark: (0.55, 0.70, 0.98))
        }
    }

    private static func dynamic(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

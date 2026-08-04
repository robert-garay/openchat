import Foundation

/// Reduces markdown content to a single line of plain text for use in
/// list-row subtitles, where syntax markers (`**`, `#`, `-`, `` ` ``, ...)
/// would otherwise render as literal characters instead of being formatted.
enum MarkdownPreviewFormatter {
    static func plainText(from content: String) -> String {
        let blocks = MarkdownContentParser.blocks(from: content)
        let segments = blocks.compactMap(plainSegment)
        return segments
            .joined(separator: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func plainSegment(_ block: MarkdownBlock) -> String? {
        switch block {
        case .heading(_, let text), .paragraph(let text), .blockquote(let text):
            return plainInlineText(text)
        case .unorderedList(let items), .orderedList(let items):
            return items.map(plainInlineText).joined(separator: ", ")
        case .code(_, let code):
            return code
        case .thematicBreak:
            return nil
        }
    }

    private static func plainInlineText(_ text: String) -> String {
        String(MarkdownInlineFormatter.attributed(from: text).characters)
    }
}

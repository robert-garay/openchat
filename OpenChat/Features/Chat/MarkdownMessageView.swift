import SwiftUI
import UIKit

/// Renders LLM reply content with ChatGPT-style markdown: headings, lists,
/// blockquotes, inline emphasis/links/code, and fenced code blocks with copy.
struct MarkdownMessageView: View {
    let content: String
    let isUserMessage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownContentParser.blocks(from: content).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineAttributed(text))
                .font(headingFont(level))
                .fontWeight(level <= 2 ? .bold : .semibold)
                .textSelection(.enabled)
                .foregroundStyle(isUserMessage ? .white : .primary)
                .padding(.top, level == 1 ? 4 : 2)

        case .paragraph(let text):
            Text(inlineAttributed(text))
                .font(.body)
                .textSelection(.enabled)
                .foregroundStyle(isUserMessage ? .white : .primary)
                .fixedSize(horizontal: false, vertical: true)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.body)
                            .foregroundStyle(isUserMessage ? .white.opacity(0.85) : .secondary)
                        Text(inlineAttributed(item))
                            .font(.body)
                            .textSelection(.enabled)
                            .foregroundStyle(isUserMessage ? .white : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(isUserMessage ? .white.opacity(0.85) : .secondary)
                            .frame(minWidth: 20, alignment: .trailing)
                        Text(inlineAttributed(item))
                            .font(.body)
                            .textSelection(.enabled)
                            .foregroundStyle(isUserMessage ? .white : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(isUserMessage ? Color.white.opacity(0.45) : Color.secondary.opacity(0.45))
                    .frame(width: 3)
                Text(inlineAttributed(text))
                    .font(.body)
                    .italic()
                    .textSelection(.enabled)
                    .foregroundStyle(isUserMessage ? .white.opacity(0.9) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)

        case .code(let language, let code):
            CodeBlockView(language: language, code: code)

        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)
                .opacity(isUserMessage ? 0.35 : 1)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .body
        }
    }

    private func inlineAttributed(_ text: String) -> AttributedString {
        MarkdownInlineFormatter.attributed(from: text)
    }
}

// MARK: - Parsing

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case blockquote(String)
    case code(language: String?, code: String)
    case thematicBreak
}

enum MarkdownContentParser {
    static func blocks(from content: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        let parts = content.components(separatedBy: "```")
        for (index, part) in parts.enumerated() {
            if index % 2 == 0 {
                result.append(contentsOf: parseTextBlocks(part))
            } else {
                result.append(parseCodeFence(part))
            }
        }
        return result
    }

    private static func parseCodeFence(_ part: String) -> MarkdownBlock {
        let lines = part.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let firstLine = lines.first.map(String.init) ?? ""
        let looksLikeLanguageTag = !firstLine.isEmpty
            && firstLine.count < 32
            && firstLine.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "_" }
        let language = looksLikeLanguageTag ? firstLine : nil
        let code: String
        if looksLikeLanguageTag, lines.count > 1 {
            code = String(lines[1])
        } else {
            code = part
        }
        return .code(language: language, code: code.trimmingCharacters(in: .newlines))
    }

    private static func parseTextBlocks(_ text: String) -> [MarkdownBlock] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                index += 1
            } else if isThematicBreak(trimmed) {
                blocks.append(.thematicBreak)
                index += 1
            } else if let item = parseUnorderedItem(trimmed) {
                let parsed = consumeList(from: lines, start: index, firstItem: item, parseItem: parseUnorderedItem)
                blocks.append(.unorderedList(parsed.items))
                index = parsed.nextIndex
            } else if let item = parseOrderedItem(trimmed) {
                let parsed = consumeList(from: lines, start: index, firstItem: item, parseItem: parseOrderedItem)
                blocks.append(.orderedList(parsed.items))
                index = parsed.nextIndex
            } else if trimmed.hasPrefix(">") {
                let parsed = consumeBlockquote(from: lines, start: index, firstLine: trimmed)
                blocks.append(.blockquote(parsed.text))
                index = parsed.nextIndex
            } else {
                let parsed = consumeParagraph(from: lines, start: index, firstLine: trimmed)
                blocks.append(.paragraph(parsed.text))
                index = parsed.nextIndex
            }
        }

        return blocks
    }

    private static func consumeList(
        from lines: [String],
        start: Int,
        firstItem: String,
        parseItem: (String) -> String?
    ) -> (items: [String], nextIndex: Int) {
        var items = [firstItem]
        var index = start + 1
        while index < lines.count {
            let next = lines[index].trimmingCharacters(in: .whitespaces)
            if next.isEmpty { break }
            guard let more = parseItem(next) else { break }
            items.append(more)
            index += 1
        }
        return (items, index)
    }

    private static func consumeBlockquote(
        from lines: [String],
        start: Int,
        firstLine: String
    ) -> (text: String, nextIndex: Int) {
        var quoteLines = [stripBlockquotePrefix(firstLine)]
        var index = start + 1
        while index < lines.count {
            let next = lines[index].trimmingCharacters(in: .whitespaces)
            if next.isEmpty || !next.hasPrefix(">") { break }
            quoteLines.append(stripBlockquotePrefix(next))
            index += 1
        }
        return (quoteLines.joined(separator: "\n"), index)
    }

    private static func consumeParagraph(
        from lines: [String],
        start: Int,
        firstLine: String
    ) -> (text: String, nextIndex: Int) {
        var paragraphLines = [firstLine]
        var index = start + 1
        while index < lines.count {
            let next = lines[index].trimmingCharacters(in: .whitespaces)
            if next.isEmpty || startsNewBlock(next) { break }
            paragraphLines.append(next)
            index += 1
        }
        return (paragraphLines.joined(separator: "\n"), index)
    }

    private static func startsNewBlock(_ line: String) -> Bool {
        parseHeading(line) != nil
            || isThematicBreak(line)
            || parseUnorderedItem(line) != nil
            || parseOrderedItem(line) != nil
            || line.hasPrefix(">")
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for character in line {
            guard character == "#" else { break }
            level += 1
            if level > 6 { return nil }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.isEmpty || rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .heading(level: level, text: text)
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let compacted = line.filter { !$0.isWhitespace }
        guard compacted.count >= 3 else { return false }
        return compacted.allSatisfy { $0 == "-" }
            || compacted.allSatisfy { $0 == "*" }
            || compacted.allSatisfy { $0 == "_" }
    }

    private static func parseUnorderedItem(_ line: String) -> String? {
        let prefixes = ["- ", "* ", "+ ", "• "]
        for prefix in prefixes where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func parseOrderedItem(_ line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let number = line[..<dotIndex]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        var rest = line[line.index(after: dotIndex)...]
        guard rest.first == " " else { return nil }
        rest = rest.dropFirst()
        return String(rest)
    }

    private static func stripBlockquotePrefix(_ line: String) -> String {
        var rest = line.dropFirst() // >
        if rest.first == " " { rest = rest.dropFirst() }
        return String(rest)
    }
}

enum MarkdownInlineFormatter {
    static func attributed(from text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard var attributed = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }

        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].font = .body.monospaced()
            attributed[run.range].backgroundColor = Color.primary.opacity(0.08)
        }
        return attributed
    }
}

// MARK: - Code block

private struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.uppercased() ?? "CODE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    Haptics.light()
                    withAnimation(Theme.springFast) { didCopy = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation(Theme.springFast) { didCopy = false }
                    }
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.3))
        )
    }
}

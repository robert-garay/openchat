import SwiftUI
import UIKit

/// Renders LLM reply content with ChatGPT-style markdown: headings, lists,
/// blockquotes, inline emphasis/links/code, and fenced code blocks with copy.
///
/// `Equatable` + `.equatable()` lets parents (composer keystrokes, streaming
/// siblings) refresh without re-parsing unchanged message bodies.
struct MarkdownMessageView: View, Equatable {
    let content: String
    let isUserMessage: Bool

    var body: some View {
        let blocks = MarkdownContentParser.blocks(from: content)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            SelectableText(
                attributedString: inlineAttributed(text),
                foregroundColor: isUserMessage ? .white : .label,
                linkColor: isUserMessage ? .white : .link,
                font: headingUIFont(level, weight: level <= 2 ? .bold : .semibold)
            )
            .padding(.top, level == 1 ? 4 : 2)

        case .paragraph(let text):
            SelectableText(
                attributedString: inlineAttributed(text),
                foregroundColor: isUserMessage ? .white : .label,
                linkColor: isUserMessage ? .white : .link
            )
            .fixedSize(horizontal: false, vertical: true)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.body)
                            .foregroundStyle(isUserMessage ? .white.opacity(0.85) : .secondary)
                        SelectableText(
                            attributedString: inlineAttributed(item),
                            foregroundColor: isUserMessage ? .white : .label,
                            linkColor: isUserMessage ? .white : .link
                        )
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
                        SelectableText(
                            attributedString: inlineAttributed(item),
                            foregroundColor: isUserMessage ? .white : .label,
                            linkColor: isUserMessage ? .white : .link
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(isUserMessage ? Color.white.opacity(0.45) : Color.secondary.opacity(0.45))
                    .frame(width: 3)
                SelectableText(
                    attributedString: inlineAttributed(text),
                    foregroundColor: isUserMessage ? .white.withAlphaComponent(0.9) : .secondaryLabel,
                    linkColor: isUserMessage ? .white : .link,
                    font: .italicBody
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)

        case .code(let language, let code):
            CodeBlockView(language: language, code: code)

        case .table(let table):
            MarkdownTableView(table: table, isUserMessage: isUserMessage)

        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)
                .opacity(isUserMessage ? 0.35 : 1)
        }
    }

    private func headingUIFont(_ level: Int, weight: UIFont.Weight) -> UIFont {
        let textStyle: UIFont.TextStyle
        switch level {
        case 1: textStyle = .title2
        case 2: textStyle = .title3
        case 3: textStyle = .headline
        default: textStyle = .body
        }
        return UIFont.preferredFont(forTextStyle: textStyle, weight: weight)
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
    case table(MarkdownTable)
}

enum MarkdownTableAlignment: Equatable {
    case leading, center, trailing
}

struct MarkdownTable: Equatable {
    let headers: [String]
    let rows: [[String]]
    let alignments: [MarkdownTableAlignment]

    func alignment(at index: Int) -> MarkdownTableAlignment {
        guard index >= 0, index < alignments.count else { return .leading }
        return alignments[index]
    }
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

    private static func parseTable(from lines: [String], start: Int) -> (table: MarkdownTable, nextIndex: Int)? {
        var index = start
        var rawRows: [[String]] = []

        while index < lines.count {
            let line = lines[index]
            guard line.contains("|") else { break }
            rawRows.append(cells(from: line))
            index += 1
        }

        guard rawRows.count >= 2 else { return nil }
        let separator = rawRows[1]
        guard isTableSeparator(separator) else { return nil }

        let headers = rawRows[0]
        let columnCount = headers.count
        guard columnCount > 0,
              separator.count == columnCount,
              rawRows.dropFirst(2).allSatisfy({ $0.count == columnCount }) else {
            return nil
        }

        let alignments = separator.map { alignment(from: $0) }
        let rows = Array(rawRows.dropFirst(2))

        return (MarkdownTable(headers: headers, rows: rows, alignments: alignments), index)
    }

    private static func cells(from line: String) -> [String] {
        var parts = line.components(separatedBy: "|")
        if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true, line.hasPrefix("|") {
            parts.removeFirst()
        }
        if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true, line.hasSuffix("|") {
            parts.removeLast()
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ cells: [String]) -> Bool {
        cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 3 else { return false }
            let hasLeadingColon = trimmed.hasPrefix(":")
            let hasTrailingColon = trimmed.hasSuffix(":")
            let body = trimmed.dropFirst(hasLeadingColon ? 1 : 0).dropLast(hasTrailingColon ? 1 : 0)
            return body.allSatisfy { $0 == "-" || $0 == "_" }
        }
    }

    private static func alignment(from cell: String) -> MarkdownTableAlignment {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        let hasLeadingColon = trimmed.hasPrefix(":")
        let hasTrailingColon = trimmed.hasSuffix(":")
        if hasLeadingColon && hasTrailingColon { return .center }
        if hasTrailingColon { return .trailing }
        return .leading
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
            } else if let parsed = parseTable(from: lines, start: index) {
                blocks.append(.table(parsed.table))
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
            if next.contains("|"), parseTable(from: lines, start: index) != nil { break }
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
                Text(CodeSyntaxHighlighter.highlight(code: code, language: language))
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

// MARK: - Table

private struct MarkdownTableView: View {
    let table: MarkdownTable
    let isUserMessage: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                    SelectableText(
                        attributedString: inlineAttributed(header),
                        foregroundColor: isUserMessage ? .white : .label,
                        linkColor: isUserMessage ? .white : .link,
                        font: .preferredFont(forTextStyle: .body, weight: .semibold)
                    )
                    .gridColumnAlignment(columnAlignment(for: table.alignment(at: index)))
                }
            }

            GridRow {
                Divider()
                    .gridCellColumns(table.headers.count)
            }

            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                        SelectableText(
                            attributedString: inlineAttributed(cell),
                            foregroundColor: isUserMessage ? .white : .label,
                            linkColor: isUserMessage ? .white : .link
                        )
                        .gridColumnAlignment(columnAlignment(for: table.alignment(at: index)))
                    }
                }
            }
        }
    }

    private func inlineAttributed(_ text: String) -> AttributedString {
        MarkdownInlineFormatter.attributed(from: text)
    }

    private func columnAlignment(for alignment: MarkdownTableAlignment) -> HorizontalAlignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - Selectable text

/// A non-editable, selectable `UITextView` wrapper that exposes the native iOS
/// text-selection handles and the full system menu (Copy, Share, Look Up, Translate).
private struct SelectableText: UIViewRepresentable {
    let attributedString: AttributedString
    let foregroundColor: UIColor
    let linkColor: UIColor
    let font: UIFont?

    init(
        attributedString: AttributedString,
        foregroundColor: UIColor,
        linkColor: UIColor,
        font: UIFont? = nil
    ) {
        self.attributedString = attributedString
        self.foregroundColor = foregroundColor
        self.linkColor = linkColor
        self.font = font
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.maximumNumberOfLines = 0
        textView.dataDetectorTypes = []
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let ns = NSAttributedString(attributedString)
        let mutable = NSMutableAttributedString(attributedString: ns)

        // Convert SwiftUI-style inline presentation intents to explicit UIKit font traits
        // so the non-editable UITextView renders bold, italic, and code consistently.
        applyInlinePresentationIntents(to: mutable)

        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.addAttribute(.foregroundColor, value: foregroundColor, range: fullRange)

        if let font = font {
            mutable.addAttribute(.font, value: font, range: fullRange)
        }

        textView.attributedText = mutable
        textView.linkTextAttributes = [
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
    }

    private func applyInlinePresentationIntents(to mutable: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.inlinePresentationIntent, in: fullRange, options: []) { value, range, _ in
            guard let intent = value as? InlinePresentationIntent else { return }
            let currentFont = mutable.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
                ?? .preferredFont(forTextStyle: .body)

            var symbolicTraits: UIFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) {
                symbolicTraits.insert(.traitBold)
            }
            if intent.contains(.emphasized) {
                symbolicTraits.insert(.traitItalic)
            }

            if intent.contains(.code) {
                let monoFont = UIFont.monospacedSystemFont(ofSize: currentFont.pointSize, weight: .regular)
                mutable.addAttribute(.font, value: monoFont, range: range)
            } else if !symbolicTraits.isEmpty {
                let descriptor = currentFont.fontDescriptor.withSymbolicTraits(symbolicTraits)
                let newFont = UIFont(descriptor: descriptor ?? currentFont.fontDescriptor, size: currentFont.pointSize)
                mutable.addAttribute(.font, value: newFont, range: range)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width.isFinite, width > 0 else {
            return nil
        }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitting.height)
    }
}

extension UIFont {
    static func preferredFont(forTextStyle style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        return UIFont.systemFont(ofSize: base.pointSize, weight: weight)
    }

    static var italicBody: UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            .withSymbolicTraits(.traitItalic)
        return UIFont(descriptor: descriptor ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body), size: 0)
    }
}

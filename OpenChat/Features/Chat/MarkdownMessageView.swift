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
    var isStreaming: Bool = false

    var body: some View {
        if isStreaming {
            // Cheap plain-text path while tokens are arriving so the UI keeps up.
            Text(content)
                .font(.body)
                .textSelection(.enabled)
                .foregroundStyle(isUserMessage ? .white : .primary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let blocks = MarkdownContentParser.blocks(from: content)
            let groups = groupedBlocks(blocks)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    groupView(group)
                }
            }
        }
    }

    @ViewBuilder
    private func groupView(_ group: BlockGroup) -> some View {
        switch group {
        case .text(let blocks):
            MarkdownTextBlockView(blocks: blocks, isUserMessage: isUserMessage)
        case .single(let block):
            singleBlockView(block)
        }
    }

    @ViewBuilder
    private func singleBlockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .table(let table):
            MarkdownTableView(table: table, isUserMessage: isUserMessage)
        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)
                .opacity(isUserMessage ? 0.35 : 1)
        default:
            EmptyView()
        }
    }

    private func groupedBlocks(_ blocks: [MarkdownBlock]) -> [BlockGroup] {
        var groups: [BlockGroup] = []
        var currentTextBlocks: [MarkdownBlock] = []

        for block in blocks {
            if block.isTextBlock {
                currentTextBlocks.append(block)
            } else {
                if !currentTextBlocks.isEmpty {
                    groups.append(.text(currentTextBlocks))
                    currentTextBlocks = []
                }
                groups.append(.single(block))
            }
        }
        if !currentTextBlocks.isEmpty {
            groups.append(.text(currentTextBlocks))
        }
        return groups
    }

    private func inlineAttributed(_ text: String) -> AttributedString {
        MarkdownInlineFormatter.attributed(from: text)
    }
}

private enum BlockGroup {
    case text([MarkdownBlock])
    case single(MarkdownBlock)
}

private extension MarkdownBlock {
    var isTextBlock: Bool {
        switch self {
        case .heading, .paragraph, .unorderedList, .orderedList, .blockquote:
            return true
        case .code, .table, .thematicBreak:
            return false
        }
    }
}

// MARK: - Selectable text block

/// Renders a contiguous group of markdown text blocks in a single non-editable,
/// selectable `UITextView`. This gives the native iOS text-selection handles and
/// lets the user drag the selection across paragraphs, list items, and headings.
private struct MarkdownTextBlockView: UIViewRepresentable {
    let blocks: [MarkdownBlock]
    let isUserMessage: Bool

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
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        if #available(iOS 18.1, *) {
            textView.writingToolsBehavior = .none
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let mutable = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                mutable.append(NSAttributedString(string: "\n"))
            }
            let isFirst = index == 0
            let isLast = index == blocks.count - 1
            mutable.append(attributedString(for: block, isFirstBlock: isFirst, isLastBlock: isLast))
        }
        textView.attributedText = mutable
        textView.linkTextAttributes = [
            .foregroundColor: isUserMessage ? UIColor.white : UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width.isFinite, width > 0 else {
            return nil
        }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitting.height)
    }

    private func attributedString(
        for block: MarkdownBlock,
        isFirstBlock: Bool,
        isLastBlock: Bool
    ) -> NSAttributedString {
        switch block {
        case .heading(let level, let text):
            let ns = NSAttributedString(MarkdownInlineFormatter.attributed(from: text))
            let mutable = NSMutableAttributedString(attributedString: ns)
            applyForegroundColor(mutable, color: isUserMessage ? .white : .label)
            applyFont(mutable, font: headingUIFont(level, weight: level <= 2 ? .bold : .semibold))
            applyInlinePresentationIntents(to: mutable)
            applyParagraphSpacing(
                mutable,
                before: isFirstBlock ? 0 : (level == 1 ? 4 : 2),
                after: isLastBlock ? 0 : 10
            )
            return mutable

        case .paragraph(let text):
            let ns = NSAttributedString(MarkdownInlineFormatter.attributed(from: text))
            let mutable = NSMutableAttributedString(attributedString: ns)
            applyForegroundColor(mutable, color: isUserMessage ? .white : .label)
            applyFont(mutable, font: .preferredFont(forTextStyle: .body))
            applyInlinePresentationIntents(to: mutable)
            applyParagraphSpacing(mutable, before: 0, after: isLastBlock ? 0 : 10)
            return mutable

        case .unorderedList(let items):
            let result = NSMutableAttributedString()
            for (index, item) in items.enumerated() {
                if index > 0 {
                    result.append(NSAttributedString(string: "\n"))
                }
                let isLastItem = index == items.count - 1
                let spacingAfter: CGFloat = isLastItem ? (isLastBlock ? 0 : 10) : 6
                let bullet = NSAttributedString(string: "• ", attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: isUserMessage ? UIColor.white.withAlphaComponent(0.85) : UIColor.secondaryLabel,
                ])
                result.append(bullet)
                let ns = NSAttributedString(MarkdownInlineFormatter.attributed(from: item))
                let mutable = NSMutableAttributedString(attributedString: ns)
                applyForegroundColor(mutable, color: isUserMessage ? .white : .label)
                applyFont(mutable, font: .preferredFont(forTextStyle: .body))
                applyInlinePresentationIntents(to: mutable)
                applyParagraphSpacing(mutable, before: 0, after: spacingAfter)
                result.append(mutable)
            }
            return result

        case .orderedList(let items):
            let result = NSMutableAttributedString()
            for (index, item) in items.enumerated() {
                if index > 0 {
                    result.append(NSAttributedString(string: "\n"))
                }
                let isLastItem = index == items.count - 1
                let spacingAfter: CGFloat = isLastItem ? (isLastBlock ? 0 : 10) : 6
                let number = NSAttributedString(string: "\(index + 1). ", attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: isUserMessage ? UIColor.white.withAlphaComponent(0.85) : UIColor.secondaryLabel,
                ])
                result.append(number)
                let ns = NSAttributedString(MarkdownInlineFormatter.attributed(from: item))
                let mutable = NSMutableAttributedString(attributedString: ns)
                applyForegroundColor(mutable, color: isUserMessage ? .white : .label)
                applyFont(mutable, font: .preferredFont(forTextStyle: .body))
                applyInlinePresentationIntents(to: mutable)
                applyParagraphSpacing(mutable, before: 0, after: spacingAfter)
                result.append(mutable)
            }
            return result

        case .blockquote(let text):
            let ns = NSAttributedString(MarkdownInlineFormatter.attributed(from: text))
            let mutable = NSMutableAttributedString(attributedString: ns)
            applyForegroundColor(mutable, color: isUserMessage ? UIColor.white.withAlphaComponent(0.9) : UIColor.secondaryLabel)
            applyFont(mutable, font: .italicBody)
            applyInlinePresentationIntents(to: mutable)
            applyParagraphSpacing(
                mutable,
                before: isFirstBlock ? 0 : 2,
                after: isLastBlock ? 0 : 10
            )
            return mutable

        case .code, .table, .thematicBreak:
            return NSAttributedString()
        }
    }

    private func applyForegroundColor(_ mutable: NSMutableAttributedString, color: UIColor) {
        let fullRange = NSRange(location: 0, length: mutable.length)
        guard fullRange.length > 0 else { return }
        mutable.addAttribute(.foregroundColor, value: color, range: fullRange)
    }

    private func applyFont(_ mutable: NSMutableAttributedString, font: UIFont) {
        let fullRange = NSRange(location: 0, length: mutable.length)
        guard fullRange.length > 0 else { return }
        mutable.addAttribute(.font, value: font, range: fullRange)
    }

    private func applyParagraphSpacing(_ mutable: NSMutableAttributedString, before: CGFloat, after: CGFloat) {
        let fullRange = NSRange(location: 0, length: mutable.length)
        guard fullRange.length > 0 else { return }
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        mutable.addAttribute(.paragraphStyle, value: style, range: fullRange)
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
                    Text(inlineAttributed(header))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isUserMessage ? .white : .primary)
                        .textSelection(.enabled)
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
                        Text(inlineAttributed(cell))
                            .font(.body)
                            .foregroundStyle(isUserMessage ? .white : .primary)
                            .textSelection(.enabled)
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

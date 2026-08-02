import SwiftUI
import UIKit

/// Renders a message's content as a mix of native markdown text and fenced
/// code blocks. Deliberately lightweight — no third-party dependency — but
/// covers what actually shows up in LLM replies: bold/italic, links, lists,
/// and ```code``` blocks with a one-tap copy button.
struct MarkdownMessageView: View {
    let content: String
    let isUserMessage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(attributed(from: text))
                            .textSelection(.enabled)
                            .foregroundStyle(isUserMessage ? .white : .primary)
                    }
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                }
            }
        }
    }

    private func attributed(from text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text.trimmingCharacters(in: .whitespacesAndNewlines),
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private enum Segment {
        case text(String)
        case code(language: String?, code: String)
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        let parts = content.components(separatedBy: "```")
        for (index, part) in parts.enumerated() {
            if index % 2 == 0 {
                result.append(.text(part))
            } else {
                let lines = part.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                let firstLine = lines.first.map(String.init) ?? ""
                let looksLikeLanguageTag = !firstLine.isEmpty && firstLine.count < 20 && !firstLine.contains(" ")
                let language = looksLikeLanguageTag ? firstLine : nil
                let code: String
                if looksLikeLanguageTag, lines.count > 1 {
                    code = String(lines[1])
                } else {
                    code = part
                }
                result.append(.code(language: language, code: code.trimmingCharacters(in: .newlines)))
            }
        }
        return result
    }
}

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

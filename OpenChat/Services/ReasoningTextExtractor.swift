import Foundation

/// Pulls model "thinking" out of assistant text that wraps it in `<think>…</think>`
/// (common for open reasoning models when the provider does not send a separate field).
enum ReasoningTextExtractor {
    private static let openTag = "<think>"
    private static let closeTag = "</think>"

    struct Extraction: Equatable, Sendable {
        var reasoning: String
        var content: String
    }

    /// Returns separated reasoning + answer when `text` contains think tags; otherwise `nil`.
    static func extract(from text: String) -> Extraction? {
        guard text.contains(openTag) else { return nil }

        var reasoningParts: [String] = []
        var contentParts: [String] = []
        var remaining = text[...]

        while let openRange = remaining.range(of: openTag) {
            let before = remaining[..<openRange.lowerBound]
            if !before.isEmpty {
                contentParts.append(String(before))
            }
            remaining = remaining[openRange.upperBound...]

            if let closeRange = remaining.range(of: closeTag) {
                reasoningParts.append(String(remaining[..<closeRange.lowerBound]))
                remaining = remaining[closeRange.upperBound...]
            } else {
                // Unclosed tag: treat the rest as reasoning (still streaming).
                reasoningParts.append(String(remaining))
                remaining = ""
                break
            }
        }

        if !remaining.isEmpty {
            contentParts.append(String(remaining))
        }

        let reasoning = reasoningParts
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let content = contentParts
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reasoning.isEmpty || text.contains(openTag) else { return nil }
        return Extraction(reasoning: reasoning, content: content)
    }
}

/// Incremental splitter for streamed tokens that may include `<think>` blocks.
struct ThinkTagStreamSplitter: Sendable {
    private var pending = ""
    private var inThink = false

    struct Slice: Equatable, Sendable {
        var reasoning: String = ""
        var content: String = ""
    }

    mutating func push(_ chunk: String) -> Slice {
        guard !chunk.isEmpty else { return Slice() }
        pending += chunk
        return drain(finished: false)
    }

    mutating func finish() -> Slice {
        drain(finished: true)
    }

    private mutating func drain(finished: Bool) -> Slice {
        var reasoning = ""
        var content = ""

        while !pending.isEmpty {
            if inThink {
                if let close = pending.range(of: "</think>") {
                    reasoning += pending[..<close.lowerBound]
                    pending = String(pending[close.upperBound...])
                    inThink = false
                    continue
                }
                if finished {
                    reasoning += pending
                    pending = ""
                } else if let holdCount = partialTagSuffixCount(in: pending, tag: "</think>") {
                    let keepIndex = pending.index(pending.endIndex, offsetBy: -holdCount)
                    reasoning += pending[..<keepIndex]
                    pending = String(pending[keepIndex...])
                } else {
                    reasoning += pending
                    pending = ""
                }
                break
            }

            if let open = pending.range(of: "<think>") {
                content += pending[..<open.lowerBound]
                pending = String(pending[open.upperBound...])
                inThink = true
                continue
            }

            // Hold back a prefix that could still become `<think>`.
            if !finished, let holdCount = partialTagSuffixCount(in: pending, tag: "<think>") {
                let keepIndex = pending.index(pending.endIndex, offsetBy: -holdCount)
                content += pending[..<keepIndex]
                pending = String(pending[keepIndex...])
            } else {
                content += pending
                pending = ""
            }
            break
        }

        return Slice(reasoning: reasoning, content: content)
    }

    private func partialTagSuffixCount(in text: String, tag: String) -> Int? {
        let maxHold = tag.count - 1
        guard maxHold > 0, !text.isEmpty else { return nil }
        let hold = min(text.count, maxHold)
        for size in stride(from: hold, through: 1, by: -1) {
            let suffix = text.suffix(size)
            if tag.hasPrefix(suffix) {
                return size
            }
        }
        return nil
    }
}

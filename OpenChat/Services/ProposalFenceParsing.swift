import Foundation

/// Shared fence/tag extraction for proposal parsers (memory, rules, etc.).
enum ProposalFenceParsing {
    struct Patterns: Sendable {
        private let capture: [NSRegularExpression?]
        private let strip: [NSRegularExpression?]

        init(fence: String, tag: String, openFence: String, openTag: String) {
            capture = [fence, tag].map { try? NSRegularExpression(pattern: $0) }
            strip = [fence, tag, openFence, openTag].map { try? NSRegularExpression(pattern: $0) }
        }

        func extractBodies(from markdown: String) -> [String] {
            var bodies: [String] = []
            for rx in capture {
                guard let rx else { continue }
                rx.enumerateMatches(
                    in: markdown,
                    range: NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
                ) { match, _, _ in
                    guard let match, let range = Range(match.range(at: 1), in: markdown) else { return }
                    bodies.append(String(markdown[range]).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            return bodies
        }

        func strippingFences(from markdown: String) -> String {
            var result = markdown
            for rx in strip {
                guard let rx else { continue }
                result = rx.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..<result.endIndex, in: result),
                    withTemplate: ""
                )
            }
            return result
                .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

import Foundation

enum RuleActionParser {
    private static let fence = #"```openchat-rule\s*([\s\S]*?)```"#
    private static let tag = #"<rule_proposal>([\s\S]*?)</rule_proposal>"#

    static func parse(_ markdown: String) -> [RuleProposal] {
        dedupe(parseBlocks(markdown, fence) + parseBlocks(markdown, tag))
    }

    static func strippingFences(from markdown: String) -> String {
        var r = markdown
        for p in [fence, tag] {
            guard let rx = try? NSRegularExpression(pattern: p) else { continue }
            r = rx.stringByReplacingMatches(in: r, range: NSRange(r.startIndex..<r.endIndex, in: r), withTemplate: "")
        }
        return r.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseBlocks(_ markdown: String, _ pattern: String) -> [RuleProposal] {
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
        var out: [RuleProposal] = []
        rx.enumerateMatches(in: markdown, range: NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)) { m, _, _ in
            guard let m, let r = Range(m.range(at: 1), in: markdown) else { return }
            out += decode(String(markdown[r]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out
    }

    private struct RuleEntry: Decodable {
        var content: String
        var scope: String
    }

    private struct RuleEntryList: Decodable {
        var rules: [RuleEntry]
    }

    private static func decode(_ body: String) -> [RuleProposal] {
        let data = Data(body.utf8)
        if let entry = try? JSONDecoder().decode(RuleEntry.self, from: data) {
            return norm(entry)
        }
        if let container = try? JSONDecoder().decode(RuleEntryList.self, from: data) {
            return container.rules.compactMap { norm($0).first }
        }
        return []
    }

    private static func norm(_ entry: RuleEntry) -> [RuleProposal] {
        let content = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let scope = RuleScope(rawValue: entry.scope) else { return [] }
        return [RuleProposal(content: content, scope: scope)]
    }

    private static func dedupe(_ proposals: [RuleProposal]) -> [RuleProposal] {
        var seen = Set<String>()
        return proposals.filter {
            let key = normalize($0.content)
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func normalize(_ content: String) -> String {
        content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }
}

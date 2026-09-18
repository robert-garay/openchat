import Foundation

enum RuleActionParser {
    private static let patterns = ProposalFenceParsing.Patterns(
        fence: #"```openchat-rule\s*([\s\S]*?)```"#,
        tag: #"<rule_proposal>([\s\S]*?)</rule_proposal>"#,
        openFence: #"```openchat-rule[\s\S]*$"#,
        openTag: #"<rule_proposal>[\s\S]*$"#
    )

    static func parse(_ markdown: String) -> [RuleProposal] {
        dedupe(patterns.extractBodies(from: markdown).flatMap(decode))
    }

    static func strippingFences(from markdown: String) -> String {
        patterns.strippingFences(from: markdown)
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

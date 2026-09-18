import Foundation
struct MemoryProposal: Equatable, Identifiable, Sendable { var id = UUID(); var content: String }
enum MemoryActionParser {
    private static let patterns = ProposalFenceParsing.Patterns(
        fence: #"```openchat-memory\s*([\s\S]*?)```"#,
        tag: #"<memory_proposal>([\s\S]*?)</memory_proposal>"#,
        openFence: #"```openchat-memory[\s\S]*$"#,
        openTag: #"<memory_proposal>[\s\S]*$"#
    )

    static func parse(_ markdown: String) -> [MemoryProposal] {
        dedupe(patterns.extractBodies(from: markdown).flatMap(decode))
    }

    static func strippingFences(from markdown: String) -> String {
        patterns.strippingFences(from: markdown)
    }

    private static func decode(_ body: String) -> [MemoryProposal] {
        let data = Data(body.utf8)
        if let e = try? JSONDecoder().decode([String:String].self, from: data), let m = e["memory"] { return norm(m) }
        if let e = try? JSONDecoder().decode([String:[String]].self, from: data), let ms = e["memories"] { return ms.compactMap { norm($0).first } }
        return body.split(whereSeparator: \.isNewline).compactMap { norm(String($0)).first }
    }
    private static func norm(_ raw: String) -> [MemoryProposal] {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? [] : [MemoryProposal(content: t)]
    }
    private static func dedupe(_ ps: [MemoryProposal]) -> [MemoryProposal] {
        var seen = Set<String>(); return ps.filter { let k = MemoryStore.normalizeContent($0.content); guard !k.isEmpty, !seen.contains(k) else { return false }; seen.insert(k); return true }
    }
}

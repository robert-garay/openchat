import Foundation
struct MemoryProposal: Equatable, Identifiable, Sendable { var id = UUID(); var content: String }
enum MemoryActionParser {
    private static let fence = #"```openchat-memory\s*([\s\S]*?)```"#
    private static let tag = #"<memory_proposal>([\s\S]*?)</memory_proposal>"#
    private static let openFence = #"```openchat-memory[\s\S]*$"#
    private static let openTag = #"<memory_proposal>[\s\S]*$"#
    static func parse(_ markdown: String) -> [MemoryProposal] { dedupe(parseBlocks(markdown, fence) + parseBlocks(markdown, tag)) }
    static func strippingFences(from markdown: String) -> String {
        var r = markdown
        for p in [fence, tag] {
            guard let rx = try? NSRegularExpression(pattern: p) else { continue }
            r = rx.stringByReplacingMatches(in: r, range: NSRange(r.startIndex..<r.endIndex, in: r), withTemplate: "")
        }
        for p in [openFence, openTag] {
            guard let rx = try? NSRegularExpression(pattern: p) else { continue }
            r = rx.stringByReplacingMatches(in: r, range: NSRange(r.startIndex..<r.endIndex, in: r), withTemplate: "")
        }
        return r.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func parseBlocks(_ markdown: String, _ pattern: String) -> [MemoryProposal] {
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
        var out: [MemoryProposal] = []
        rx.enumerateMatches(in: markdown, range: NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)) { m,_,_ in
            guard let m, let r = Range(m.range(at: 1), in: markdown) else { return }
            out += decode(String(markdown[r]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out
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

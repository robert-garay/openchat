import Foundation
import Observation
import SwiftData
@MainActor @Observable final class MemoryStore {
    static let maxInjectionItems = 40, maxInjectionCharacters = 8000
    private let useKey = "com.openchat.memory.useInChats", confirmKey = "com.openchat.memory.requireConfirmation"
    private let defaults: UserDefaults
    private(set) var useInChats: Bool, requireConfirmation: Bool
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        useInChats = defaults.object(forKey: useKey) == nil ? false : defaults.bool(forKey: useKey)
        requireConfirmation = defaults.object(forKey: confirmKey) == nil ? true : defaults.bool(forKey: confirmKey)
    }
    static func shouldUseMemory(isTemporary: Bool, useInChats: Bool) -> Bool { useInChats && !isTemporary }
    func setUseInChats(_ v: Bool) { useInChats = v; defaults.set(v, forKey: useKey) }
    func setRequireConfirmation(_ v: Bool) { requireConfirmation = v; defaults.set(v, forKey: confirmKey) }
    func fetchItems(modelContext: ModelContext) throws -> [MemoryItem] { try modelContext.fetch(FetchDescriptor(sortBy: [SortDescriptor(\.pinned, order: .reverse), SortDescriptor(\.updatedAt, order: .reverse)])) }
    @discardableResult func save(content: String, source: MemorySource, modelContext: ModelContext) throws -> MemoryItem {
        let t = content.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { throw MemoryStoreError.emptyContent }
        if let m = findSimilar(try fetchItems(modelContext: modelContext), t) { m.content = t; m.updatedAt = .now; if source == .user || m.source == .user { m.source = .user } else if source == .confirmedFromChat { m.source = .confirmedFromChat }; return m }
        let i = MemoryItem(content: t, source: source); modelContext.insert(i); return i
    }
    func delete(_ i: MemoryItem, modelContext: ModelContext) { modelContext.delete(i) }
    func clearAll(modelContext: ModelContext) throws { for i in try fetchItems(modelContext: modelContext) { modelContext.delete(i) } }
    func togglePinned(_ i: MemoryItem) { i.pinned.toggle(); i.updatedAt = .now }
    func updateContent(_ i: MemoryItem, content: String, modelContext: ModelContext) throws {
        let t = content.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { throw MemoryStoreError.emptyContent }
        let rest = try fetchItems(modelContext: modelContext).filter { $0.id != i.id }
        if let m = findSimilar(rest, t) { modelContext.delete(i); m.content = t; m.updatedAt = .now; return }
        i.content = t; i.updatedAt = .now
    }
    func injectionItems(from items: [MemoryItem]) -> [MemoryItem] {
        var sel: [MemoryItem] = [], chars = 0
        for i in items.sorted(by: { $0.pinned != $1.pinned ? $0.pinned && !$1.pinned : $0.updatedAt > $1.updatedAt }) {
            guard sel.count < Self.maxInjectionItems else { break }
            let line = "- \(i.content)"; if chars + line.count + 1 > Self.maxInjectionCharacters, !sel.isEmpty { break }
            sel.append(i); chars += line.count + 1
        }
        return sel
    }
    static func contextSection(for items: [MemoryItem]) -> String? {
        guard !items.isEmpty else { return nil }
        return "## Memory\nDurable facts the user saved in OpenChat. Use when relevant. Do not invent facts beyond this list.\n\n" + items.map { "- \($0.content)" }.joined(separator: "\n")
    }
    static func modelInstruction() -> String { "The user enabled long-term memory in OpenChat. Propose durable facts using ```openchat-memory\\n{\\\"memories\\\":[\\\"fact\\\"]}\\n``` or <memory_proposal>…</memory_proposal>. No secrets. Saved after confirmation unless disabled." }
    static func normalizeContent(_ c: String) -> String {
        c.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }
    private func findSimilar(_ items: [MemoryItem], _ content: String) -> MemoryItem? { let n = Self.normalizeContent(content); return items.first { Self.normalizeContent($0.content) == n } }
}
enum MemoryStoreError: LocalizedError { case emptyContent; var errorDescription: String? { "Memory cannot be empty." } }

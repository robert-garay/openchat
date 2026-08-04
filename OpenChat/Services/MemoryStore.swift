import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class MemoryStore {
    static let maxInjectionItems = 40
    static let maxInjectionCharacters = 8000

    private let useKey = "com.openchat.memory.useInChats"
    private let confirmKey = "com.openchat.memory.requireConfirmation"

    @ObservationIgnored
    private let defaults: UserDefaults

    private(set) var useInChats: Bool
    private(set) var requireConfirmation: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: useKey) == nil {
            useInChats = false
        } else {
            useInChats = defaults.bool(forKey: useKey)
        }
        if defaults.object(forKey: confirmKey) == nil {
            requireConfirmation = true
        } else {
            requireConfirmation = defaults.bool(forKey: confirmKey)
        }
    }

    nonisolated static func shouldUseMemory(isTemporary: Bool, useInChats: Bool) -> Bool {
        useInChats && !isTemporary
    }

    func setUseInChats(_ value: Bool) {
        useInChats = value
        defaults.set(value, forKey: useKey)
    }

    func setRequireConfirmation(_ value: Bool) {
        requireConfirmation = value
        defaults.set(value, forKey: confirmKey)
    }

    func fetchItems(modelContext: ModelContext) throws -> [MemoryItem] {
        let items = try modelContext.fetch(
            FetchDescriptor<MemoryItem>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        )
        return items.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    @discardableResult
    func save(content: String, source: MemorySource, modelContext: ModelContext) throws -> MemoryItem {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MemoryStoreError.emptyContent }

        if let match = findSimilar(try fetchItems(modelContext: modelContext), trimmed) {
            match.content = trimmed
            match.updatedAt = .now
            if source == .user || match.source == .user {
                match.source = .user
            } else if source == .confirmedFromChat {
                match.source = .confirmedFromChat
            }
            return match
        }

        let item = MemoryItem(content: trimmed, source: source)
        modelContext.insert(item)
        return item
    }

    func delete(_ item: MemoryItem, modelContext: ModelContext) {
        modelContext.delete(item)
    }

    func clearAll(modelContext: ModelContext) throws {
        for item in try fetchItems(modelContext: modelContext) {
            modelContext.delete(item)
        }
    }

    func togglePinned(_ item: MemoryItem) {
        item.pinned.toggle()
        item.updatedAt = .now
    }

    func updateContent(_ item: MemoryItem, content: String, modelContext: ModelContext) throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MemoryStoreError.emptyContent }

        let others = try fetchItems(modelContext: modelContext).filter { $0.id != item.id }
        if let match = findSimilar(others, trimmed) {
            modelContext.delete(item)
            match.content = trimmed
            match.updatedAt = .now
            return
        }

        item.content = trimmed
        item.updatedAt = .now
    }

    func injectionItems(from items: [MemoryItem]) -> [MemoryItem] {
        var selected: [MemoryItem] = []
        var characters = 0
        let ordered = items.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.updatedAt > rhs.updatedAt
        }
        for item in ordered {
            guard selected.count < Self.maxInjectionItems else { break }
            let line = "- \(item.content)"
            if characters + line.count + 1 > Self.maxInjectionCharacters, !selected.isEmpty {
                break
            }
            selected.append(item)
            characters += line.count + 1
        }
        return selected
    }

    static func contextSection(for items: [MemoryItem]) -> String? {
        guard !items.isEmpty else { return nil }
        let body = items.map { "- \($0.content)" }.joined(separator: "\n")
        return "## Memory\nDurable facts the user saved in OpenChat. Use when relevant. Do not invent facts beyond this list.\n\n\(body)"
    }

    nonisolated static func modelInstruction() -> String {
        "The user enabled long-term memory in OpenChat. Propose durable facts using ```openchat-memory\\n{\\\"memories\\\":[\\\"fact\\\"]}\\n``` or <memory_proposal>…</memory_proposal>. No secrets. Saved after confirmation unless disabled."
    }

    nonisolated static func normalizeContent(_ content: String) -> String {
        content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private func findSimilar(_ items: [MemoryItem], _ content: String) -> MemoryItem? {
        let normalized = Self.normalizeContent(content)
        return items.first { Self.normalizeContent($0.content) == normalized }
    }
}

enum MemoryStoreError: LocalizedError {
    case emptyContent

    var errorDescription: String? {
        "Memory cannot be empty."
    }
}

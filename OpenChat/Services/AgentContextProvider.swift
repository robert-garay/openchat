import Foundation

/// Builds ephemeral on-device context for chat requests from sources the user enabled.
/// Context is injected into the model request only — it is not stored in chat history.
@MainActor
struct AgentContextProvider {
    var memoryItems: [MemoryItem] = []
    var memorySection: ([MemoryItem]) -> String? = { items in
        MemoryStore.contextSection(for: items)
    }

    func makeContextBlock() async -> String? {
        var sections: [String] = []

        if !memoryItems.isEmpty, let memory = memorySection(memoryItems) {
            sections.append(memory)
        }

        guard !sections.isEmpty else { return nil }

        return """
        On-device context the user enabled in OpenChat settings. Use it when relevant. \
        Do not invent memory facts beyond what appears here. \
        If they ask about saved preferences or long-term facts, prefer the Memory section.

        \(sections.joined(separator: "\n\n"))
        """
    }
}

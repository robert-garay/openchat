import SwiftData
import SwiftUI
struct MemorySettingsView: View {
    @Environment(MemoryStore.self) private var memoryStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\.MemoryItem.pinned, order: .reverse), SortDescriptor(\.MemoryItem.updatedAt, order: .reverse)]) private var items: [MemoryItem]
    var body: some View {
        List {
            Section {
                Toggle("Use memory in chats", isOn: Binding(get: { memoryStore.useInChats }, set: { memoryStore.setUseInChats($0) }))
                Toggle("Require confirmation", isOn: Binding(get: { memoryStore.requireConfirmation }, set: { memoryStore.setRequireConfirmation($0) })).disabled(!memoryStore.useInChats)
            } footer: { Text("When confirmation is off, memory proposals from chats are saved automatically. Do not store passwords, API keys, or other secrets.") }
            Section("Saved memories") {
                if items.isEmpty { Text("No memories yet.").foregroundStyle(.secondary) }
                ForEach(items) { Text($0.content) }
                Button("Add memory") { try? memoryStore.save(content: "New memory", source: .user, modelContext: modelContext) }
            }
        }.navigationTitle("Memory")
    }
}

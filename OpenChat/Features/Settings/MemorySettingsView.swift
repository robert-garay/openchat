import SwiftData
import SwiftUI

struct MemorySettingsView: View {
    @Environment(MemoryStore.self) private var memoryStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\MemoryItem.updatedAt, order: .reverse),
    ]) private var items: [MemoryItem]

    @State private var showingAddMemory = false
    @State private var editingItem: MemoryItem?
    @State private var showingClearConfirmation = false

    private var sortedItems: [MemoryItem] {
        items.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        List {
            Section {
                Toggle("Use memory in chats", isOn: Binding(
                    get: { memoryStore.useInChats },
                    set: { memoryStore.setUseInChats($0) }
                ))
                Toggle("Require confirmation", isOn: Binding(
                    get: { memoryStore.requireConfirmation },
                    set: { memoryStore.setRequireConfirmation($0) }
                ))
                .disabled(!memoryStore.useInChats)
            } footer: {
                Text("When confirmation is off, memory proposals from chats are saved automatically. Do not store passwords, API keys, or other secrets.")
            }

            Section {
                if sortedItems.isEmpty {
                    Text("No memories yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedItems) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.content)
                                    .lineLimit(3)
                                Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingItem = item }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            memoryStore.delete(sortedItems[index], modelContext: modelContext)
                        }
                        try? modelContext.save()
                    }
                }

                Button {
                    showingAddMemory = true
                } label: {
                    Label("Add memory", systemImage: "plus.circle.fill")
                }

                if !sortedItems.isEmpty {
                    Button("Clear all", role: .destructive) {
                        showingClearConfirmation = true
                    }
                }
            } header: {
                Text("Saved memories")
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddMemory) {
            MemoryEditorSheet(title: "Add memory", initialText: "") { content in
                do {
                    try memoryStore.save(content: content, source: .user, modelContext: modelContext)
                    try modelContext.save()
                } catch {
                    return error.localizedDescription
                }
                return nil
            }
        }
        .sheet(item: $editingItem) { item in
            MemoryEditorSheet(title: "Edit memory", initialText: item.content) { content in
                do {
                    try memoryStore.updateContent(item, content: content, modelContext: modelContext)
                    try modelContext.save()
                } catch {
                    return error.localizedDescription
                }
                return nil
            }
        }
        .confirmationDialog(
            "Clear all memories?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear all", role: .destructive) {
                try? memoryStore.clearAll(modelContext: modelContext)
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every saved memory on this device.")
        }
    }
}

private struct MemoryEditorSheet: View {
    let title: String
    let initialText: String
    /// Returns an error message to show, or `nil` on success.
    let onSave: (String) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Memory", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let message = onSave(text) {
                            errorMessage = message
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { text = initialText }
        }
    }
}

extension MemoryItem: Identifiable {}

import SwiftUI
import SwiftData

struct ChatRulesSheet: View {
    @Bindable var conversation: Conversation
    @Environment(\.modelContext) private var modelContext
    @Environment(RulesStore.self) private var rulesStore

    @State private var showingAddRule = false
    @State private var editingItem: RuleItem?

    private var sortedItems: [RuleItem] {
        conversation.rules.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        List {
            if sortedItems.isEmpty {
                Section("Chat rules") {
                    Text("No rules yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Chat rules") {
                    ForEach(sortedItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.content)
                                .lineLimit(3)
                            Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                rulesStore.delete(item, modelContext: modelContext)
                                try? modelContext.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingItem = item
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Color.accentColor)
                        }
                    }
                }
            }

            Section {
                Button {
                    showingAddRule = true
                } label: {
                    Label("Add rule", systemImage: "plus.circle.fill")
                }
            }
        }
        .frame(minWidth: 340)
        .sheet(isPresented: $showingAddRule) {
            RuleEditorSheet(title: "Add rule", initialText: "") { content in
                do {
                    try rulesStore.save(content: content, modelContext: modelContext, conversation: conversation)
                    try modelContext.save()
                } catch {
                    return error.localizedDescription
                }
                return nil
            }
        }
        .sheet(item: $editingItem) { item in
            RuleEditorSheet(title: "Edit rule", initialText: item.content) { content in
                do {
                    try rulesStore.updateContent(item, content: content, modelContext: modelContext)
                    try modelContext.save()
                } catch {
                    return error.localizedDescription
                }
                return nil
            }
        }
    }
}

import SwiftUI
import SwiftData

struct ChatRulesSheet: View {
    @Bindable var conversation: Conversation
    @Environment(\.modelContext) private var modelContext
    @Environment(RulesStore.self) private var rulesStore

    @State private var newRuleText = ""
    @State private var editingItem: RuleItem?
    @State private var errorMessage: String?

    private var sortedItems: [RuleItem] {
        conversation.rules.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if sortedItems.isEmpty {
                    Section {
                        Text("No rules yet.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(sortedItems) { item in
                            Button {
                                editingItem = item
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.content)
                                        .foregroundStyle(.primary)
                                        .lineLimit(3)
                                    Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Chat Rules")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                addRuleBar
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
        .frame(minWidth: 340)
    }

    private var addRuleBar: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)
            HStack(spacing: 12) {
                TextField("Add rule", text: $newRuleText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addRule)
                Button {
                    addRule()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            newRuleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color(.tertiaryLabel)
                                : Color.accentColor
                        )
                }
                .disabled(newRuleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private func addRule() {
        let content = newRuleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        do {
            try rulesStore.save(content: content, modelContext: modelContext, conversation: conversation)
            try modelContext.save()
            newRuleText = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

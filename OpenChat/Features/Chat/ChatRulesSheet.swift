import SwiftUI
import SwiftData

struct ChatRulesSheet: View {
    @Bindable var conversation: Conversation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(RulesStore.self) private var rulesStore
    @Query(sort: [SortDescriptor(\.RuleItem.updatedAt, order: .reverse)]) private var items: [RuleItem]

    @State private var showingAddRule = false
    @State private var editingItem: RuleItem?
    @State private var showingClearConfirmation = false

    private var sortedItems: [RuleItem] {
        items.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Instructions for this chat") {
                    TextEditor(text: $conversation.systemPrompt)
                        .frame(minHeight: 80)
                } footer: {
                    if conversation.isTemporary {
                        Text("Rules apply to this session only and won't persist after you leave this chat.")
                    } else {
                        Text("These instructions apply only to this conversation and override global rules when they conflict.")
                    }
                }

                Section {
                    Toggle("Use global rules in chats", isOn: Binding(
                        get: { rulesStore.useGlobalRules },
                        set: { rulesStore.setUseGlobalRules($0) }
                    ))
                    Toggle("Use chat rules", isOn: Binding(
                        get: { rulesStore.useChatRules },
                        set: { rulesStore.setUseChatRules($0) }
                    ))
                } footer: {
                    Text("Global rules apply to every chat when enabled. Chat rules are per-conversation instructions and only apply when enabled.")
                }

                Section {
                    if sortedItems.isEmpty {
                        Text("No rules yet.")
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
                                rulesStore.delete(sortedItems[index], modelContext: modelContext)
                            }
                            try? modelContext.save()
                        }
                    }

                    Button {
                        showingAddRule = true
                    } label: {
                        Label("Add rule", systemImage: "plus.circle.fill")
                    }

                    if !sortedItems.isEmpty {
                        Button("Clear all", role: .destructive) {
                            showingClearConfirmation = true
                        }
                    }
                } header: {
                    Text("Saved rules")
                }
            }
            .navigationTitle("Chat Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddRule) {
                RuleEditorSheet(title: "Add rule", initialText: "") { content in
                    do {
                        try rulesStore.save(content: content, modelContext: modelContext)
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
            .confirmationDialog(
                "Clear all rules?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear all", role: .destructive) {
                    try? rulesStore.clearAll(modelContext: modelContext)
                    try? modelContext.save()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes every saved global rule on this device.")
            }
            .onAppear {
                rulesStore.migrateLegacyGlobalRulesIfNeeded(modelContext: modelContext)
            }
        }
    }
}

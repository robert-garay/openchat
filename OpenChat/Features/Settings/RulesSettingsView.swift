import SwiftData
import SwiftUI

struct RulesSettingsView: View {
    @Environment(RulesStore.self) private var rulesStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\RuleItem.updatedAt, order: .reverse),
    ]) private var items: [RuleItem]

    @State private var showingAddRule = false
    @State private var editingItem: RuleItem?
    @State private var showingClearConfirmation = false

    private var globalItems: [RuleItem] {
        items.filter { $0.conversation == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        List {
            Section {
                Toggle("Use global rules in chats", isOn: Binding(
                    get: { rulesStore.useGlobalRules },
                    set: { rulesStore.setUseGlobalRules($0) }
                ))
                Toggle("Use chat rules", isOn: Binding(
                    get: { rulesStore.useChatRules },
                    set: { rulesStore.setUseChatRules($0) }
                ))
                Toggle("Allow assistant to propose rules", isOn: Binding(
                    get: { rulesStore.allowProposalsFromChat },
                    set: { rulesStore.setAllowProposalsFromChat($0) }
                ))
                Toggle("Require confirmation", isOn: Binding(
                    get: { rulesStore.requireConfirmation },
                    set: { rulesStore.setRequireConfirmation($0) }
                ))
                .disabled(!rulesStore.allowProposalsFromChat)
            } footer: {
                Text(
                    "Global rules apply to every chat when enabled. Chat rules are per-conversation instructions (edited from the chat composer) and only apply when enabled. Both are off by default. When the assistant is allowed to propose rules, it can suggest new global or chat rules during a conversation for you to review before they're saved."
                )
            }

            Section {
                if globalItems.isEmpty {
                    Text("No rules yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(globalItems) { item in
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

                Button {
                    showingAddRule = true
                } label: {
                    Label("Add rule", systemImage: "plus.circle.fill")
                }

                if !globalItems.isEmpty {
                    Button("Clear all", role: .destructive) {
                        showingClearConfirmation = true
                    }
                }
            } header: {
                Text("Global rules")
            }
        }
        .navigationTitle("Rules")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            rulesStore.migrateLegacyGlobalRulesIfNeeded(modelContext: modelContext)
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
                for item in globalItems {
                    rulesStore.delete(item, modelContext: modelContext)
                }
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every saved global rule on this device.")
        }
    }
}

struct RuleEditorSheet: View {
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
                    TextField("Rule", text: $text, axis: .vertical)
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

extension RuleItem: Identifiable {}

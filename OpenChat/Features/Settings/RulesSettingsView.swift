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

    private var sortedItems: [RuleItem] {
        items.sorted { $0.updatedAt > $1.updatedAt }
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
            } footer: {
                Text(
                    "Global rules apply to every chat when enabled. Chat rules are per-conversation instructions (edited from the chat composer) and only apply when enabled. Both are off by default."
                )
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
                try? rulesStore.clearAll(modelContext: modelContext)
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every saved global rule on this device.")
        }
    }
}

private struct RuleEditorSheet: View {
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

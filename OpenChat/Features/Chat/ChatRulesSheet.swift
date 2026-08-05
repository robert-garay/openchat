import SwiftUI
import SwiftData

struct ChatRulesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(RulesStore.self) private var rulesStore
    @Query(sort: [SortDescriptor(\RuleItem.updatedAt, order: .reverse)]) private var items: [RuleItem]

    @State private var showingAddRule = false

    private var sortedItems: [RuleItem] {
        items.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if sortedItems.isEmpty {
                        Text("No rules yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.content)
                                    .lineLimit(3)
                                Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button {
                        showingAddRule = true
                    } label: {
                        Label("Add rule", systemImage: "plus.circle.fill")
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
            .onAppear {
                rulesStore.migrateLegacyGlobalRulesIfNeeded(modelContext: modelContext)
            }
        }
    }
}

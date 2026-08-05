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
        VStack(alignment: .leading, spacing: 0) {
            if sortedItems.isEmpty {
                Text("No rules yet.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(sortedItems.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.content)
                            .font(.body)
                            .lineLimit(3)
                            .foregroundStyle(.primary)
                        Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if index < sortedItems.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }

            if !sortedItems.isEmpty {
                Divider()
                    .padding(.leading, 16)
            }

            Button {
                showingAddRule = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                    Text("Add rule")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .frame(minWidth: 260, minHeight: 120)
        .fixedSize(horizontal: false, vertical: true)
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

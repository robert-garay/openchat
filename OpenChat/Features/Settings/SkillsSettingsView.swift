import SwiftUI
import SwiftData

struct SkillsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Skill.name) private var skills: [Skill]
    @State private var showingEditor = false
    @State private var editingSkill: Skill?

    var body: some View {
        List {
            if skills.isEmpty {
                ContentUnavailableView("No Skills", systemImage: "bolt.slash", description: Text("Create skills to invoke with / in chat."))
            } else {
                ForEach(skills) { skill in
                    Button { editingSkill = skill } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(skill.name).foregroundStyle(.primary)
                                Spacer()
                                Text("/\(skill.slashName)").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            if !skill.skillDescription.isEmpty {
                                Text(skill.skillDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }.onDelete { offsets in offsets.forEach { modelContext.delete(skills[$0]) } }
            }
        }
        .navigationTitle("Skills").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { showingEditor = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showingEditor) { SkillEditorView(skill: nil) }
        .sheet(item: $editingSkill) { SkillEditorView(skill: $0) }
    }
}

extension Skill: Identifiable {}

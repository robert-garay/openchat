import SwiftData
import SwiftUI

struct SkillsSettingsView: View {
    @Environment(SkillsStore.self) private var skillsStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Skill.name) private var skills: [Skill]

    @State private var showingEditor = false
    @State private var editingSkill: Skill?
    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            Section {
                Toggle("Use skills in chats", isOn: Binding(
                    get: { skillsStore.isEnabled },
                    set: { skillsStore.setIsEnabled($0) }
                ))
                Toggle("Require confirmation", isOn: Binding(
                    get: { skillsStore.requireConfirmation },
                    set: { skillsStore.setRequireConfirmation($0) }
                ))
                .disabled(!skillsStore.isEnabled)
            } footer: {
                Text("Skills can be invoked with /slash-name or automatically when relevant. When confirmation is off, skills drafted from chat are saved automatically.")
            }

            Section {
                if skills.isEmpty {
                    Text("No skills yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(skills) { skill in
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
                        .contentShape(Rectangle())
                        .onTapGesture { editingSkill = skill }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            skillsStore.delete(skills[index], modelContext: modelContext)
                        }
                        try? modelContext.save()
                    }
                }

                Button {
                    showingEditor = true
                } label: {
                    Label("Add skill", systemImage: "plus.circle.fill")
                }

                if !skills.isEmpty {
                    Button("Clear all", role: .destructive) {
                        showingClearConfirmation = true
                    }
                }
            } header: {
                Text("Saved skills")
            }
        }
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) { SkillEditorView(skill: nil) }
        .sheet(item: $editingSkill) { SkillEditorView(skill: $0) }
        .confirmationDialog(
            "Clear all skills?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear all", role: .destructive) {
                try? skillsStore.clearAll(modelContext: modelContext)
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every saved skill on this device.")
        }
    }
}

extension Skill: Identifiable {}

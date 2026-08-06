import SwiftUI
import SwiftData

struct SkillEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let skill: Skill?
    var createdFromChatID: UUID? = nil
    /// Pre-fills the form from a model-drafted proposal (`create_skill`) awaiting review.
    /// Ignored when `skill` is non-nil (editing an existing skill takes priority).
    var proposal: SkillProposal? = nil
    /// Called after a successful save, in addition to dismissing — lets callers clear
    /// proposal-review state that lives outside this view.
    var onSaved: (() -> Void)? = nil
    @State private var name = ""
    @State private var slashInput = ""
    @State private var skillDescription = ""
    @State private var instructions = ""
    @State private var slashNameError: String?

    private var normalizedSlashName: String { SkillResolver.normalizeSlashName(slashInput) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !normalizedSlashName.isEmpty && slashNameError == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display Name", text: $name)
                    HStack { Text("/").foregroundStyle(.secondary); TextField("slash-name", text: $slashInput).textInputAutocapitalization(.never).autocorrectionDisabled().onChange(of: slashInput) { _, _ in validateSlashName() } }
                    if let slashNameError { Text(slashNameError).font(.caption).foregroundStyle(.red) }
                    else if !normalizedSlashName.isEmpty { Text("Invoked as /\(normalizedSlashName)").font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Identity") }
                Section { TextField("Short description", text: $skillDescription, axis: .vertical).lineLimit(2...4) } header: { Text("Description") }
                Section { TextEditor(text: $instructions).frame(minHeight: 160) } header: { Text("Instructions") }
            }
            .navigationTitle(skill == nil ? "New Skill" : "Edit Skill").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
            .onAppear {
                if let skill {
                    name = skill.name; slashInput = skill.slashName; skillDescription = skill.skillDescription; instructions = skill.instructions
                } else if let proposal {
                    name = proposal.name; slashInput = proposal.slashName; skillDescription = proposal.description; instructions = proposal.instructions
                }
                validateSlashName()
            }
        }
    }

    private func validateSlashName() {
        let normalized = normalizedSlashName
        guard !normalized.isEmpty else { slashNameError = nil; return }
        if SkillResolver.isReservedSlashName(normalized) {
            slashNameError = "This slash name is reserved for the built-in skill-builder."
            return
        }
        let existing = (try? modelContext.fetch(FetchDescriptor<Skill>())) ?? []
        slashNameError = existing.contains { $0.slashName == normalized && $0.id != skill?.id } ? "A skill with this slash name already exists." : nil
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizedSlashName
        guard !trimmedName.isEmpty, !normalized.isEmpty, slashNameError == nil else { return }
        if let skill {
            skill.name = trimmedName; skill.slashName = normalized
            skill.skillDescription = skillDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            skill.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines); skill.updatedAt = .now
        } else {
            modelContext.insert(Skill(name: trimmedName, slashName: normalized, skillDescription: skillDescription.trimmingCharacters(in: .whitespacesAndNewlines), instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines), createdFromChatID: createdFromChatID))
        }
        Haptics.success(); onSaved?(); dismiss()
    }
}

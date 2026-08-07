import SwiftUI
import SwiftData

struct RuleReviewSheet: View {
    @Environment(RulesStore.self) private var rulesStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let proposal: RuleProposal
    let conversation: Conversation
    var onSaved: ((UUID) -> Void)? = nil

    @State private var content = ""
    @State private var scope: RuleScope = .chat
    @State private var errorMessage: String?

    private var canSave: Bool { !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Rule", text: $content, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Rule")
                }
                Section {
                    Picker("Applies to", selection: $scope) {
                        Text("This chat").tag(RuleScope.chat)
                        Text("Every chat").tag(RuleScope.global)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Every chat rules apply globally, everywhere. This chat rules apply only to this conversation.")
                }
                if scope == .global && !rulesStore.useGlobalRules {
                    Section {
                        Button("Enable global rules") {
                            rulesStore.setUseGlobalRules(true)
                        }
                    } footer: {
                        Text("Global rules are currently off, so this rule won't take effect until you enable them.")
                    }
                } else if scope == .chat && !rulesStore.useChatRules {
                    Section {
                        Button("Enable chat rules") {
                            rulesStore.setUseChatRules(true)
                        }
                    } footer: {
                        Text("Chat rules are currently off, so this rule won't take effect until you enable them.")
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
            .navigationTitle("Review Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                content = proposal.content
                scope = proposal.scope
            }
        }
    }

    private func save() {
        do {
            _ = try rulesStore.save(
                content: content,
                modelContext: modelContext,
                conversation: scope == .global ? nil : conversation
            )
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        Haptics.success()
        onSaved?(proposal.id)
        dismiss()
    }
}

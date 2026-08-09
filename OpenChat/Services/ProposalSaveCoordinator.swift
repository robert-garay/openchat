import Foundation
import SwiftData

/// Shared proposal-persistence logic used by both the in-chat path
/// (`ChatViewModel+Proposals`) and the background-generation path
/// (`BackgroundGenerationService+Proposals`).
///
/// Each helper returns the number of successfully saved proposals, or the first
/// error it encounters. Callers are responsible for reporting the outcome in
/// their own UI layer.
@MainActor
enum ProposalSaveCoordinator {
    enum Result {
        case saved(count: Int)
        case failed(Error)
    }

    static func saveMemory(
        _ proposals: [MemoryProposal],
        source: MemorySource,
        memoryStore: MemoryStore,
        modelContext: ModelContext
    ) -> Result {
        var saved = 0
        for proposal in proposals {
            do {
                _ = try memoryStore.save(content: proposal.content, source: source, modelContext: modelContext)
                saved += 1
            } catch {
                return .failed(error)
            }
        }
        if saved > 0 {
            try? modelContext.save()
        }
        return .saved(count: saved)
    }

    static func saveRule(
        _ proposals: [RuleProposal],
        rulesStore: RulesStore,
        modelContext: ModelContext,
        conversation: Conversation
    ) -> Result {
        var saved = 0
        for proposal in proposals {
            do {
                _ = try rulesStore.save(
                    content: proposal.content,
                    modelContext: modelContext,
                    conversation: proposal.scope == .global ? nil : conversation
                )
                saved += 1
            } catch {
                return .failed(error)
            }
        }
        if saved > 0 {
            try? modelContext.save()
        }
        return .saved(count: saved)
    }

    static func saveSkill(
        _ proposals: [SkillProposal],
        skillsStore: SkillsStore,
        modelContext: ModelContext,
        conversation: Conversation
    ) -> Result {
        var saved = 0
        for proposal in proposals {
            do {
                _ = try skillsStore.save(
                    name: proposal.name,
                    slashName: proposal.slashName,
                    skillDescription: proposal.description,
                    instructions: proposal.instructions,
                    createdFromChatID: conversation.id,
                    modelContext: modelContext
                )
                saved += 1
            } catch {
                return .failed(error)
            }
        }
        if saved > 0 {
            try? modelContext.save()
        }
        return .saved(count: saved)
    }
}

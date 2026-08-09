import Foundation

/// Sendable-safe side channel for the non-isolated `executeTool` closure to record
/// skill tool calls into, since it cannot touch MainActor-isolated state directly.
/// Drained back on the MainActor after streaming completes.
actor SkillInvocationCollector {
    private(set) var invokedSkills: [SkillMatchable] = []
    private(set) var proposals: [SkillProposal] = []

    func recordInvoke(_ skill: SkillMatchable) {
        invokedSkills.append(skill)
    }

    func recordProposal(_ proposal: SkillProposal) {
        proposals.append(proposal)
    }
}

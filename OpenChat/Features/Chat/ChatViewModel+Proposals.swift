import Foundation
import SwiftData

@MainActor
extension ChatViewModel {
    func captureCalendarProposals(from message: ChatMessage) {
        guard dataSourceStore.canEditCalendar else { return }
        let proposals = CalendarActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        pendingCalendarActionsByMessageID[message.id] = proposals
    }

    func captureRemindersProposals(from message: ChatMessage) {
        guard dataSourceStore.canEditReminders else { return }
        let proposals = RemindersActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        pendingRemindersActionsByMessageID[message.id] = proposals
    }

    func captureContactsProposals(from message: ChatMessage) {
        guard dataSourceStore.canEditContacts else { return }
        let proposals = ContactsActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        pendingContactsActionsByMessageID[message.id] = proposals
    }

    func captureMemoryProposals(from message: ChatMessage) {
        guard shouldUseMemory else { return }
        let proposals = MemoryActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        if memoryStore.requireConfirmation {
            pendingMemoryProposalsByMessageID[message.id] = proposals
        } else {
            saveMemoryProposals(proposals, source: .auto, messageID: message.id)
        }
    }

    func saveMemoryProposals(_ proposals: [MemoryProposal], source: MemorySource, messageID: UUID) {
        var saved = 0
        for proposal in proposals {
            do {
                _ = try memoryStore.save(content: proposal.content, source: source, modelContext: modelContext)
                saved += 1
            } catch {
                memoryActionStatusByMessageID[messageID] = error.localizedDescription
                return
            }
        }
        if saved > 0 {
            try? modelContext.save()
            memoryActionStatusByMessageID[messageID] = "Memory updated."
        }
    }

    func captureRuleProposals(from message: ChatMessage) {
        guard shouldAllowRuleProposals else { return }
        let proposals = RuleActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        if rulesStore.requireConfirmation {
            pendingRuleProposalsByMessageID[message.id] = proposals
        } else {
            saveRuleProposals(proposals, messageID: message.id)
        }
    }

    func saveRuleProposals(_ proposals: [RuleProposal], messageID: UUID) {
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
                ruleActionStatusByMessageID[messageID] = error.localizedDescription
                return
            }
        }
        if saved > 0 {
            try? modelContext.save()
            ruleActionStatusByMessageID[messageID] = "Rule saved."
        }
    }

    func captureSkillProposals(_ proposals: [SkillProposal], messageID: UUID) {
        guard !proposals.isEmpty else { return }
        if skillsStore.requireConfirmation {
            pendingSkillProposalsByMessageID[messageID] = proposals
        } else {
            saveSkillProposals(proposals, messageID: messageID)
        }
    }

    func saveSkillProposals(_ proposals: [SkillProposal], messageID: UUID) {
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
                skillActionStatusByMessageID[messageID] = error.localizedDescription
                return
            }
        }
        if saved > 0 {
            try? modelContext.save()
            skillActionStatusByMessageID[messageID] = "Skill saved."
        }
    }
}

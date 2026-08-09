import Foundation
import SwiftData

@MainActor
extension ChatViewModel {
    // MARK: - Calendar / reminders / contacts actions

    func confirmCalendarActions(for messageID: UUID) async {
        guard !isApplyingCalendarActions else { return }
        guard dataSourceStore.canEditCalendar else {
            calendarActionStatusByMessageID[messageID] = CalendarEventWriterError.editingDisabled.localizedDescription
            pendingCalendarActionsByMessageID[messageID] = nil
            return
        }
        guard let proposals = pendingCalendarActionsByMessageID[messageID], !proposals.isEmpty else { return }

        isApplyingCalendarActions = true
        let results = await Task.detached(priority: .userInitiated) {
            var results: [String] = []
            for proposal in proposals {
                do {
                    results.append(try CalendarEventWriter.apply(proposal))
                } catch {
                    results.append(error.localizedDescription)
                }
            }
            return results
        }.value
        calendarActionStatusByMessageID[messageID] = results.joined(separator: "\n")
        pendingCalendarActionsByMessageID[messageID] = nil
        isApplyingCalendarActions = false
        Haptics.success()
    }

    func dismissCalendarActions(for messageID: UUID) {
        pendingCalendarActionsByMessageID[messageID] = nil
        calendarActionStatusByMessageID[messageID] = "Calendar changes discarded."
        Haptics.light()
    }

    func confirmRemindersActions(for messageID: UUID) async {
        guard !isApplyingRemindersActions else { return }
        guard dataSourceStore.canEditReminders else {
            remindersActionStatusByMessageID[messageID] = RemindersWriterError.editingDisabled.localizedDescription
            pendingRemindersActionsByMessageID[messageID] = nil
            return
        }
        guard let proposals = pendingRemindersActionsByMessageID[messageID], !proposals.isEmpty else { return }

        isApplyingRemindersActions = true
        let results = await Task.detached(priority: .userInitiated) {
            var results: [String] = []
            for proposal in proposals {
                do {
                    results.append(try RemindersWriter.apply(proposal))
                } catch {
                    results.append(error.localizedDescription)
                }
            }
            return results
        }.value
        remindersActionStatusByMessageID[messageID] = results.joined(separator: "\n")
        pendingRemindersActionsByMessageID[messageID] = nil
        isApplyingRemindersActions = false
        Haptics.success()
    }

    func dismissRemindersActions(for messageID: UUID) {
        pendingRemindersActionsByMessageID[messageID] = nil
        remindersActionStatusByMessageID[messageID] = "Reminders changes discarded."
        Haptics.light()
    }

    func confirmContactsActions(for messageID: UUID) async {
        guard !isApplyingContactsActions else { return }
        guard dataSourceStore.canEditContacts else {
            contactsActionStatusByMessageID[messageID] = ContactsWriterError.editingDisabled.localizedDescription
            pendingContactsActionsByMessageID[messageID] = nil
            return
        }
        guard let proposals = pendingContactsActionsByMessageID[messageID], !proposals.isEmpty else { return }

        isApplyingContactsActions = true
        let results = await Task.detached(priority: .userInitiated) {
            var results: [String] = []
            for proposal in proposals {
                do {
                    results.append(try ContactsWriter.apply(proposal))
                } catch {
                    results.append(error.localizedDescription)
                }
            }
            return results
        }.value
        contactsActionStatusByMessageID[messageID] = results.joined(separator: "\n")
        pendingContactsActionsByMessageID[messageID] = nil
        isApplyingContactsActions = false
        Haptics.success()
    }

    func dismissContactsActions(for messageID: UUID) {
        pendingContactsActionsByMessageID[messageID] = nil
        contactsActionStatusByMessageID[messageID] = "Contacts changes discarded."
        Haptics.light()
    }

    // MARK: - Memory / rule / skill proposals

    func confirmMemoryProposals(for messageID: UUID) {
        guard let proposals = pendingMemoryProposalsByMessageID[messageID], !proposals.isEmpty else { return }
        saveMemoryProposals(proposals, source: .confirmedFromChat, messageID: messageID)
        pendingMemoryProposalsByMessageID[messageID] = nil
        try? modelContext.save()
        Haptics.success()
    }

    func dismissMemoryProposals(for messageID: UUID) {
        pendingMemoryProposalsByMessageID[messageID] = nil
        memoryActionStatusByMessageID[messageID] = "Memory discarded."
        Haptics.light()
    }

    /// Clears a pending skill proposal after the user saved it via the review sheet
    /// (SkillEditorView performs the actual save; this only clears the bookkeeping).
    func clearSkillProposalAfterReview(for messageID: UUID) {
        pendingSkillProposalsByMessageID[messageID] = nil
        skillActionStatusByMessageID[messageID] = "Skill saved."
        Haptics.success()
    }

    func dismissSkillProposals(for messageID: UUID) {
        pendingSkillProposalsByMessageID[messageID] = nil
        skillActionStatusByMessageID[messageID] = "Skill discarded."
        Haptics.light()
    }

    /// Clears a pending rule proposal after the user saved it via the review sheet
    /// (RuleReviewSheet performs the actual save; this only clears the bookkeeping).
    /// Removes only the reviewed proposal — any remaining proposals for this message stay pending.
    func clearRuleProposalAfterReview(for messageID: UUID, proposalID: UUID) {
        guard var proposals = pendingRuleProposalsByMessageID[messageID] else { return }
        proposals.removeAll { $0.id == proposalID }
        if proposals.isEmpty {
            pendingRuleProposalsByMessageID[messageID] = nil
            ruleActionStatusByMessageID[messageID] = "Rule saved."
        } else {
            pendingRuleProposalsByMessageID[messageID] = proposals
        }
        Haptics.success()
    }

    func dismissRuleProposals(for messageID: UUID) {
        pendingRuleProposalsByMessageID[messageID] = nil
        ruleActionStatusByMessageID[messageID] = "Rule discarded."
        Haptics.light()
    }

    // MARK: - Capture / save helpers

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
        switch ProposalSaveCoordinator.saveMemory(
            proposals,
            source: source,
            memoryStore: memoryStore,
            modelContext: modelContext
        ) {
        case .saved(let savedCount):
            if savedCount > 0 {
                memoryActionStatusByMessageID[messageID] = "Memory updated."
            }
        case .failed(let error):
            memoryActionStatusByMessageID[messageID] = error.localizedDescription
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
        switch ProposalSaveCoordinator.saveRule(
            proposals,
            rulesStore: rulesStore,
            modelContext: modelContext,
            conversation: conversation
        ) {
        case .saved(let savedCount):
            if savedCount > 0 {
                ruleActionStatusByMessageID[messageID] = "Rule saved."
            }
        case .failed(let error):
            ruleActionStatusByMessageID[messageID] = error.localizedDescription
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
        switch ProposalSaveCoordinator.saveSkill(
            proposals,
            skillsStore: skillsStore,
            modelContext: modelContext,
            conversation: conversation
        ) {
        case .saved(let savedCount):
            if savedCount > 0 {
                skillActionStatusByMessageID[messageID] = "Skill saved."
            }
        case .failed(let error):
            skillActionStatusByMessageID[messageID] = error.localizedDescription
        }
    }
}

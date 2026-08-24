import Foundation
import SwiftData

@MainActor
extension ChatViewModel {
    func setupGenerationObserver() {
        let center = NotificationCenter.default
        generationObserver = center.addObserver(
            forName: .bgGenDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let conversationID = notification.userInfo?["conversationID"] as? UUID,
                  let event = notification.userInfo?["event"] as? BackgroundGenerationEvent
            else { return }
            Task { @MainActor in
                guard let self else { return }
                guard conversationID == self.conversation.id else { return }

                switch event {
                case .started:
                    self.isStreaming = true
                case .progress:
                    break
                case .completed, .cancelled, .failed:
                    self.isStreaming = false
                    self.refreshPendingProposals()
                    try? self.modelContext.save()
                }
            }
        }

        calendarProposalObserver = center.addObserver(
            forName: .bgGenCapturedCalendarProposals,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let messageID = notification.userInfo?["messageID"] as? UUID,
                  let proposals = notification.userInfo?["proposals"] as? [CalendarActionProposal]
            else { return }
            Task { @MainActor in
                guard let self else { return }
                self.pendingCalendarActionsByMessageID[messageID] = proposals
            }
        }

        remindersProposalObserver = center.addObserver(
            forName: .bgGenCapturedRemindersProposals,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let messageID = notification.userInfo?["messageID"] as? UUID,
                  let proposals = notification.userInfo?["proposals"] as? [RemindersActionProposal]
            else { return }
            Task { @MainActor in
                guard let self else { return }
                self.pendingRemindersActionsByMessageID[messageID] = proposals
            }
        }

        contactsProposalObserver = center.addObserver(
            forName: .bgGenCapturedContactsProposals,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let messageID = notification.userInfo?["messageID"] as? UUID,
                  let proposals = notification.userInfo?["proposals"] as? [ContactsActionProposal]
            else { return }
            Task { @MainActor in
                guard let self else { return }
                self.pendingContactsActionsByMessageID[messageID] = proposals
            }
        }

        memoryProposalObserver = center.addObserver(
            forName: .bgGenCapturedMemoryProposals,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let messageID = notification.userInfo?["messageID"] as? UUID,
                  let proposals = notification.userInfo?["proposals"] as? [MemoryProposal]
            else { return }
            Task { @MainActor in
                guard let self else { return }
                self.pendingMemoryProposalsByMessageID[messageID] = proposals
            }
        }

        ruleProposalObserver = center.addObserver(
            forName: .bgGenCapturedRuleProposals,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let messageID = notification.userInfo?["messageID"] as? UUID,
                  let proposals = notification.userInfo?["proposals"] as? [RuleProposal]
            else { return }
            Task { @MainActor in
                guard let self else { return }
                self.pendingRuleProposalsByMessageID[messageID] = proposals
            }
        }

        skillProposalObserver = center.addObserver(
            forName: .bgGenCapturedSkillProposals,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let messageID = notification.userInfo?["messageID"] as? UUID,
                  let proposals = notification.userInfo?["proposals"] as? [SkillProposal]
            else { return }
            Task { @MainActor in
                guard let self else { return }
                self.pendingSkillProposalsByMessageID[messageID] = proposals
            }
        }
    }

    func refreshPendingProposals() {
        pendingCalendarActionsByMessageID.removeAll()
        pendingRemindersActionsByMessageID.removeAll()
        pendingContactsActionsByMessageID.removeAll()
        pendingMemoryProposalsByMessageID.removeAll()
        pendingRuleProposalsByMessageID.removeAll()
        calendarActionStatusByMessageID.removeAll()
        remindersActionStatusByMessageID.removeAll()
        contactsActionStatusByMessageID.removeAll()
        memoryActionStatusByMessageID.removeAll()
        ruleActionStatusByMessageID.removeAll()
        // Skill proposals and their statuses are captured from tool calls during
        // streaming, not from message content, so they cannot be restored here.
        // Keep the existing entries so background generations still show them.

        for message in conversation.sortedMessages where message.role == .assistant {
            captureCalendarProposals(from: message)
            captureRemindersProposals(from: message)
            captureContactsProposals(from: message)
            captureMemoryProposals(from: message)
            captureRuleProposals(from: message)
        }
    }

    func cancelStreaming() {
        BackgroundGenerationService.shared.cancelGeneration(for: conversation.id)
    }

    func requestNotificationAuthorizationIfNeeded() {
        Task {
            _ = await NotificationService.shared.requestAuthorizationIfNeeded()
        }
    }

    /// Marks every message in this conversation as read. Called when the chat becomes visible.
    func markAllRead() {
        guard conversation.hasUnreadMessages else { return }
        conversation.markAllRead()
        try? modelContext.save()

        NotificationService.shared.clearNotification(conversationID: conversation.id)
        let unreadCount = BackgroundGenerationService.unreadConversationCount(modelContext: modelContext)
        Task {
            await NotificationService.shared.setBadgeCount(unreadCount)
        }
    }
}

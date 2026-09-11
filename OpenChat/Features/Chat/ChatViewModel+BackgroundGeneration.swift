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
        pendingMemoryProposalsByMessageID.removeAll()
        pendingRuleProposalsByMessageID.removeAll()
        memoryActionStatusByMessageID.removeAll()
        ruleActionStatusByMessageID.removeAll()
        // Skill proposals and their statuses are captured from tool calls during
        // streaming, not from message content, so they cannot be restored here.
        // Keep the existing entries so background generations still show them.

        for message in conversation.sortedMessages where message.role == .assistant {
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

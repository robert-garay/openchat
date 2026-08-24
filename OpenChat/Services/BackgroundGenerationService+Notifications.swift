import Foundation
import SwiftData
import UIKit

extension BackgroundGenerationService {
    // MARK: - Completion handling

    func notifyCompletion(
        conversationID: UUID,
        messageID: UUID,
        conversationTitle: String,
        assistantMessage: ChatMessage,
        modelContext: ModelContext,
        error: Error? = nil
    ) {
        let didFail = error != nil || assistantMessage.errorMessage != nil
        notify(
            event: didFail ? .failed : .completed,
            conversationID: conversationID,
            messageID: messageID
        )

        // Post a local notification unless this is the conversation currently
        // on screen — matching Messages/Slack, which still banner a finished
        // reply in a different chat even while the app is foregrounded.
        let isConversationVisible = UIApplication.shared.applicationState == .active
            && visibleConversationID == conversationID
        if !isConversationVisible {
            let unreadCount = Self.unreadConversationCount(modelContext: modelContext)
            Task {
                await NotificationService.shared.scheduleResponseNotification(
                    conversationID: conversationID,
                    conversationTitle: conversationTitle,
                    messagePreview: assistantMessage.content,
                    failed: didFail,
                    badgeCount: unreadCount
                )
            }
        }
    }

    /// Number of conversations with at least one unread assistant message —
    /// the standard basis for an app icon badge count.
    static func unreadConversationCount(modelContext: ModelContext) -> Int {
        let conversations = (try? modelContext.fetch(FetchDescriptor<Conversation>())) ?? []
        return conversations.filter(\.hasUnreadMessages).count
    }

    func notifyProgress(activityID: String?, conversationID: UUID, messageID: UUID, elapsed: TimeInterval) {
        notify(event: .progress(elapsed: elapsed), conversationID: conversationID, messageID: messageID)
        Task {
            await LiveActivityService.shared.update(
                activityID: activityID,
                status: .generating(elapsed: elapsed)
            )
        }
    }

    func notify(event: BackgroundGenerationEvent, conversationID: UUID, messageID: UUID) {
        NotificationCenter.default.post(
            name: .bgGenDidUpdate,
            object: nil,
            userInfo: [
                "event": event,
                "conversationID": conversationID,
                "messageID": messageID
            ]
        )
    }
}

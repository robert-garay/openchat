import Foundation
import UserNotifications
import UIKit

/// Schedules local notifications for assistant responses that finish while the
/// app is in the background.
@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()

    nonisolated(unsafe) private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
        let category = UNNotificationCategory(
            identifier: "OPENCHAT_RESPONSE",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// Requests alert/badge/sound authorization the first time it is needed.
    /// Subsequent calls return the current authorization status without prompting again.
    func requestAuthorizationIfNeeded() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    /// Posts a notification that tapping opens the relevant conversation. Uses a
    /// stable per-conversation identifier so a second finished reply in the same
    /// chat replaces the previous banner instead of stacking another one.
    func scheduleResponseNotification(
        conversationID: UUID,
        conversationTitle: String,
        messagePreview: String,
        failed: Bool,
        badgeCount: Int
    ) async {
        let content = UNMutableNotificationContent()
        content.title = conversationTitle
        let preview = messagePreview
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let trimmedPreview = preview.count > 120 ? String(preview.prefix(120)) + "…" : preview
        content.body = failed
            ? "Couldn't finish — tap to retry."
            : (trimmedPreview.isEmpty ? "Tap to read the response." : trimmedPreview)
        content.sound = failed ? nil : .default
        content.userInfo = ["conversationID": conversationID.uuidString]
        content.categoryIdentifier = "OPENCHAT_RESPONSE"
        content.threadIdentifier = conversationID.uuidString
        content.badge = NSNumber(value: badgeCount)

        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier(for: conversationID),
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule response notification: \(error.localizedDescription)")
        }
    }

    /// Removes any pending or delivered notification for `conversationID`, e.g.
    /// when the user opens that chat and no longer needs to be told about it.
    func clearNotification(conversationID: UUID) {
        let identifier = Self.notificationIdentifier(for: conversationID)
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Sets the app icon badge to the given unread-conversation count.
    func setBadgeCount(_ count: Int) async {
        try? await center.setBadgeCount(count)
    }

    private static func notificationIdentifier(for conversationID: UUID) -> String {
        "response-\(conversationID.uuidString)"
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Scheduling already skips the conversation currently on screen, so any
        // notification that reaches here — foreground or not — is for a chat the
        // user isn't looking at and should banner just like Messages.
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let idString = userInfo["conversationID"] as? String,
           let conversationID = UUID(uuidString: idString) {
            NotificationCenter.default.post(
                name: .notificationOpenedConversation,
                object: nil,
                userInfo: ["conversationID": conversationID]
            )
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let notificationOpenedConversation = Notification.Name("com.openchat.notificationOpenedConversation")
}

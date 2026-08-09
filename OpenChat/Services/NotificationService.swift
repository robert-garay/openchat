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

    /// Posts a notification that tapping opens the relevant conversation.
    func scheduleResponseNotification(
        conversationID: UUID,
        conversationTitle: String,
        messagePreview: String,
        failed: Bool
    ) async {
        let content = UNMutableNotificationContent()
        content.title = failed ? "OpenChat — Response failed" : "OpenChat — Response ready"
        let preview = messagePreview
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let trimmedPreview = preview.count > 120 ? String(preview.prefix(120)) + "…" : preview
        content.body = failed
            ? "Tap to view the details."
            : (trimmedPreview.isEmpty ? "Tap to read the response." : trimmedPreview)
        content.sound = failed ? nil : .default
        content.userInfo = ["conversationID": conversationID.uuidString]
        content.categoryIdentifier = "OPENCHAT_RESPONSE"

        let request = UNNotificationRequest(
            identifier: "response-\(conversationID.uuidString)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule response notification: \(error.localizedDescription)")
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // If the app happens to be in the foreground when a completion notification
        // fires, don't show it — the UI already updates live.
        completionHandler([])
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

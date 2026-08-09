import Foundation
import ActivityKit

/// Manages the Live Activity shown in the Dynamic Island / lock screen while a
/// response is being generated in the background.
final class LiveActivityService: @unchecked Sendable {
    static let shared = LiveActivityService()
    private init() {}

    private var activities: [String: Activity<OpenChatLiveActivityAttributes>] = [:]

    /// Starts a new Live Activity and returns its ID, or nil if ActivityKit is unavailable
    /// or the user has disabled Live Activities.
    @discardableResult
    func start(conversationTitle: String, modelName: String?) -> String? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
        guard Activity<OpenChatLiveActivityAttributes>.activities.isEmpty else {
            // Only one OpenChat activity at a time.
            return Activity<OpenChatLiveActivityAttributes>.activities.first?.id
        }

        let attributes = OpenChatLiveActivityAttributes(
            conversationTitle: conversationTitle,
            modelName: modelName ?? "Assistant"
        )
        let initialState = OpenChatLiveActivityAttributes.ContentState(
            status: .generating(elapsed: 0),
            progress: 0,
            detail: "Generating response…"
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil),
                pushType: nil
            )
            activities[activity.id] = activity
            return activity.id
        } catch {
            return nil
        }
    }

    /// Updates the Live Activity with a new status. Safe to call with a nil ID.
    func update(activityID: String?, status: OpenChatLiveActivityAttributes.Status) async {
        guard let activityID, let activity = activities[activityID] else { return }

        let contentState: OpenChatLiveActivityAttributes.ContentState
        switch status {
        case .generating(let elapsed):
            let detail = elapsed < 60
                ? "Generating response…"
                : "Still generating \(Int(elapsed / 60))m…"
            contentState = OpenChatLiveActivityAttributes.ContentState(
                status: .generating(elapsed: elapsed),
                progress: 0,
                detail: detail
            )
        case .completed:
            contentState = OpenChatLiveActivityAttributes.ContentState(
                status: .completed,
                progress: 1,
                detail: "Response ready"
            )
        case .failed:
            contentState = OpenChatLiveActivityAttributes.ContentState(
                status: .failed,
                progress: 1,
                detail: "Response failed"
            )
        }

        await activity.update(ActivityContent(state: contentState, staleDate: nil))
    }

    /// Ends the Live Activity, showing the final state for a moment before dismissal.
    func end(activityID: String?) async {
        guard let activityID, let activity = activities.removeValue(forKey: activityID) else { return }
        let finalState = OpenChatLiveActivityAttributes.ContentState(
            status: .completed,
            progress: 1,
            detail: "Response ready"
        )
        await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .default)
    }
}

import Foundation
import ActivityKit

/// Manages the Live Activity shown in the Dynamic Island / lock screen while a
/// response is being generated in the background.
actor LiveActivityService {
    static let shared = LiveActivityService()
    private init() {}

    private var activityIDs: Set<String> = []

    /// Starts a new Live Activity and returns its ID, or nil if ActivityKit is unavailable
    /// or the user has disabled Live Activities.
    @discardableResult
    func start(conversationTitle: String, modelName: String?) async -> String? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }

        if let existingID = Activity<OpenChatLiveActivityAttributes>.activities.first?.id {
            // Only one OpenChat activity at a time; reuse a stale one if present.
            activityIDs.insert(existingID)
            return existingID
        }

        let attributes = OpenChatLiveActivityAttributes(
            conversationTitle: conversationTitle,
            modelName: modelName ?? "Assistant"
        )
        let initialState = OpenChatLiveActivityAttributes.ContentState(
            status: .generating(elapsed: 0),
            detail: "Generating response…"
        )

        do {
            let activity = try await Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil),
                pushType: nil
            )
            activityIDs.insert(activity.id)
            return activity.id
        } catch {
            return nil
        }
    }

    /// Updates the Live Activity with a new status. Safe to call with a nil ID.
    func update(activityID: String?, status: OpenChatLiveActivityAttributes.Status) async {
        guard let activityID, activityIDs.contains(activityID) else { return }
        guard let activity = Activity<OpenChatLiveActivityAttributes>.activities.first(where: { $0.id == activityID }) else {
            activityIDs.remove(activityID)
            return
        }

        let contentState: OpenChatLiveActivityAttributes.ContentState
        switch status {
        case .generating(let elapsed):
            let detail = elapsed < 60
                ? "Generating response…"
                : "Still generating \(Int(elapsed / 60))m…"
            contentState = OpenChatLiveActivityAttributes.ContentState(
                status: .generating(elapsed: elapsed),
                detail: detail
            )
        case .completed:
            contentState = OpenChatLiveActivityAttributes.ContentState(
                status: .completed,
                detail: "Response ready"
            )
        case .failed:
            contentState = OpenChatLiveActivityAttributes.ContentState(
                status: .failed,
                detail: "Response failed"
            )
        }

        await activity.update(ActivityContent(state: contentState, staleDate: nil))
    }

    /// Ends the Live Activity, showing the final state for a moment before dismissal.
    func end(activityID: String?, status: OpenChatLiveActivityAttributes.Status = .completed) async {
        guard let activityID, activityIDs.remove(activityID) != nil else { return }
        guard let activity = Activity<OpenChatLiveActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }

        let detail = status == .failed ? "Response failed" : "Response ready"
        let finalState = OpenChatLiveActivityAttributes.ContentState(
            status: status,
            detail: detail
        )
        await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .default)
    }
}

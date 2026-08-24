import Foundation
import SwiftData
import Observation
import ActivityKit
import UserNotifications
import UIKit

/// Coordinates assistant-response generation that outlives any single `ChatViewModel`.
///
/// Generation tasks run on the main actor so they can mutate the SwiftData message
/// directly (keeping the UI live while the chat is visible). The service owns the
/// tasks, so navigating away from a thread does not cancel the stream. When the app
/// moves to the background the task requests background execution time and updates
/// a Live Activity; on completion it posts a local notification if the app is still
/// backgrounded. While any generation is active and the app is foregrounded, the
/// idle timer is disabled so the screen doesn't auto-lock mid-response.
@MainActor
final class BackgroundGenerationService {
    static let shared = BackgroundGenerationService()
    private init() {}

    // MARK: - Dependencies

    var providerStore: ProviderStore?
    var dataSourceStore: AgentDataSourceStore?
    var webSearchStore: WebSearchStore?
    var rulesStore: RulesStore?
    var memoryStore: MemoryStore?
    var skillsStore: SkillsStore?
    var modelContainer: ModelContainer?

    /// The conversation currently visible to the user. Used to decide whether a
    /// finished assistant turn should be marked unread.
    var visibleConversationID: UUID?

    // MARK: - Active tasks

    private struct ActiveTask {
        let taskID: UUID
        let task: Task<Void, Never>
        let assistantMessageID: UUID
        let conversationID: UUID
        let startDate: Date
        var activityID: String?
        var backgroundTaskID: UIBackgroundTaskIdentifier?
    }

    struct BuildTurnsResult {
        let turns: [ChatTurn]
        let tools: [ChatToolDefinition]
        let executeTool: @Sendable (ChatToolCall) async throws -> String
        let skillCollector: SkillInvocationCollector
        let skillMatches: [SkillMatchable]
    }

    private var tasks: [UUID: ActiveTask] = [:]

    // MARK: - Configuration

    func configure(
        providerStore: ProviderStore,
        dataSourceStore: AgentDataSourceStore,
        webSearchStore: WebSearchStore,
        rulesStore: RulesStore,
        memoryStore: MemoryStore,
        skillsStore: SkillsStore,
        modelContainer: ModelContainer
    ) {
        self.providerStore = providerStore
        self.dataSourceStore = dataSourceStore
        self.webSearchStore = webSearchStore
        self.rulesStore = rulesStore
        self.memoryStore = memoryStore
        self.skillsStore = skillsStore
        self.modelContainer = modelContainer
    }

    func setVisibleConversationID(_ id: UUID?) {
        visibleConversationID = id
    }

    func clearVisibleConversationID(ifEquals id: UUID) {
        guard visibleConversationID == id else { return }
        visibleConversationID = nil
    }

    // MARK: - Public API

    /// Returns true if a generation is currently running for `conversationID`.
    func isGenerating(for conversationID: UUID) -> Bool {
        tasks[conversationID] != nil
    }

    /// Begins generating a response for `assistantMessage` in `conversation`.
    /// The assistant message should already be inserted into the conversation and
    /// marked `isStreaming == true` by the caller.
    @discardableResult
    func startGeneration(
        for assistantMessage: ChatMessage,
        in conversation: Conversation,
        using modelContext: ModelContext
    ) -> UUID {
        let conversationID = conversation.id

        // Cancel any existing generation for this conversation (shouldn't happen
        // because callers guard with `!isStreaming`, but be defensive).
        cancelGeneration(for: conversationID)

        let taskID = UUID()
        let startDate = Date()

        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "OpenChat generation \(conversationID)") { @MainActor [weak self, conversationID] in
            // The system is about to suspend us; end the expired task and record
            // that it is no longer active so performGeneration's cleanup is safe.
            guard let self else { return }
            if var active = tasks[conversationID] {
                endBackgroundTask(active.backgroundTaskID)
                active.backgroundTaskID = .invalid
                tasks[conversationID] = active
            }
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performGeneration(
                taskID: taskID,
                conversationID: conversationID,
                assistantMessage: assistantMessage,
                conversation: conversation,
                modelContext: modelContext,
                startDate: startDate
            )
        }

        tasks[conversationID] = ActiveTask(
            taskID: taskID,
            task: task,
            assistantMessageID: assistantMessage.id,
            conversationID: conversationID,
            startDate: startDate,
            activityID: nil,
            backgroundTaskID: backgroundTaskID
        )
        updateIdleTimer()

        notify(event: .started, conversationID: conversationID, messageID: assistantMessage.id)
        return taskID
    }

    func cancelGeneration(for conversationID: UUID) {
        guard let active = tasks.removeValue(forKey: conversationID) else { return }
        updateIdleTimer()
        active.task.cancel()
        endBackgroundTask(active.backgroundTaskID)
        Task {
            // Immediate dismissal: a cancelled response isn't a failure, so it
            // shouldn't flash the red "failed" ring before disappearing.
            await LiveActivityService.shared.end(activityID: active.activityID, status: .failed, dismissalPolicy: .immediate)
        }
    }

    // MARK: - Generation

    private func performGeneration(
        taskID: UUID,
        conversationID: UUID,
        assistantMessage: ChatMessage,
        conversation: Conversation,
        modelContext: ModelContext,
        startDate: Date
    ) async {
        var activityID = tasks[conversationID]?.activityID
        var finalActivityStatus: OpenChatLiveActivityAttributes.Status?
        defer {
            Task { @MainActor in
                if let active = tasks[conversationID], active.taskID == taskID {
                    endBackgroundTask(active.backgroundTaskID)
                    tasks.removeValue(forKey: conversationID)
                    updateIdleTimer()
                }
            }
            // Computed here (not at task start) so a successful completion's
            // timestamp reflects when the response actually finished.
            let status = finalActivityStatus ?? .completed(at: .now)
            let dismissalPolicy: ActivityUIDismissalPolicy = {
                switch status {
                case .completed: .after(Date.now.addingTimeInterval(15 * 60))
                case .generating, .failed: .default
                }
            }()
            Task {
                await LiveActivityService.shared.end(activityID: activityID, status: status, dismissalPolicy: dismissalPolicy)
            }
        }

        guard let providerStore, let dataSourceStore, let webSearchStore, let rulesStore, let memoryStore, let skillsStore else {
            finalActivityStatus = .failed
            finishWithError(
                message: assistantMessage,
                conversation: conversation,
                error: ChatServiceError.serviceNotConfigured,
                modelContext: modelContext,
                conversationID: conversationID
            )
            return
        }

        guard let provider = providerStore.provider(withID: conversation.providerID),
              let model = providerStore.model(providerID: conversation.providerID, modelID: conversation.modelID)
        else {
            finalActivityStatus = .failed
            finishWithError(
                message: assistantMessage,
                conversation: conversation,
                error: ChatServiceError.providerOrModelNotFound,
                modelContext: modelContext,
                conversationID: conversationID
            )
            return
        }

        let apiKey = providerStore.apiKey(for: provider)
        guard !provider.requiresAPIKey || apiKey != nil else {
            finalActivityStatus = .failed
            finishWithError(
                message: assistantMessage,
                conversation: conversation,
                error: ChatServiceError.missingAPIKey,
                modelContext: modelContext,
                conversationID: conversationID
            )
            return
        }

        // Start the Live Activity now that we know the generation will actually run.
        if !Task.isCancelled {
            let liveActivityID = await LiveActivityService.shared.start(
                conversationTitle: conversation.isTemporary ? "Temporary Chat" : conversation.title,
                modelName: model.displayName
            )
            if var active = tasks[conversationID], active.taskID == taskID {
                active.activityID = liveActivityID
                tasks[conversationID] = active
            }
            activityID = liveActivityID
        }

        let client = ChatService.client(for: provider.apiFormat)
        let baseURL = provider.baseURL
        let modelID = model.id
        let supportsImageGen = model.supportsImageGen
        let supportsEffort = model.supportsEffort
        let hasSeparateThinkingToggle = model.hasSeparateThinkingToggle
        let isReasoningMandatory = model.isReasoningMandatory
        let supportedEffortLevels = model.supportedEffortLevels
        let effortLevel = conversation.effortLevel
        let isReasoningEnabled = conversation.isReasoningEnabled
        let effectiveEffortLevel: EffortLevel? = {
            guard supportsEffort, !supportedEffortLevels.isEmpty else { return nil }
            if hasSeparateThinkingToggle, !isReasoningEnabled {
                return supportedEffortLevels.first
            }
            return supportedEffortLevels.contains(effortLevel) ? effortLevel : (supportedEffortLevels.last ?? .default)
        }()
        let effectiveReasoningEnabled: Bool? = {
            guard supportsEffort, hasSeparateThinkingToggle else { return nil }
            return isReasoningEnabled && !isReasoningMandatory
        }()

        do {
            let result = try await buildTurns(
                conversation: conversation,
                assistantMessage: assistantMessage,
                model: model,
                provider: provider,
                apiKey: apiKey,
                memoryStore: memoryStore,
                rulesStore: rulesStore,
                dataSourceStore: dataSourceStore,
                webSearchStore: webSearchStore,
                skillsStore: skillsStore,
                modelContext: modelContext,
                effectiveEffortLevel: effectiveEffortLevel,
                effectiveReasoningEnabled: effectiveReasoningEnabled
            )

            var workingTurns = result.turns
            var continuationAttempts = 0
            let maxContinuationAttempts = 1

            while true {
                do {
                    try await runStream(
                        client: client,
                        modelID: modelID,
                        baseURL: baseURL,
                        apiKey: apiKey,
                        turns: workingTurns,
                        tools: result.tools,
                        executeTool: result.executeTool,
                        supportsImageGen: supportsImageGen,
                        effort: effectiveEffortLevel,
                        reasoningEnabled: effectiveReasoningEnabled,
                        assistantMessage: assistantMessage,
                        activityID: activityID,
                        conversationID: conversationID,
                        startDate: startDate
                    )
                    break
                } catch ChatServiceError.connectionDropped
                where continuationAttempts < maxContinuationAttempts
                    && !assistantMessage.content.isEmpty
                    && result.tools.isEmpty {
                    // Silent auto-retry, resume in place: nothing that streamed
                    // has been lost (Task 8's flush fix guarantees that), so
                    // we ask the model to continue from exactly where it
                    // stopped rather than re-sending the original request.
                    // Continuation is only attempted when no tools were available
                    // for this generation: the continuation only knows the
                    // pre-loop turns and the streamed text, not any tool
                    // calls/results the client's internal tool loop may have
                    // already run — resuming would risk silently re-executing
                    // (and re-billing) those tools.
                    continuationAttempts += 1
                    await NetworkMonitor.shared.waitForConnection()
                    try Task.checkCancellation()
                    workingTurns = Self.continuationTurns(
                        previousTurns: workingTurns,
                        partialContent: assistantMessage.content
                    )
                }
            }

            await applyPostStream(
                assistantMessage: assistantMessage,
                conversation: conversation,
                skillCollector: result.skillCollector,
                skillMatches: result.skillMatches,
                skillsStore: skillsStore,
                memoryStore: memoryStore,
                rulesStore: rulesStore,
                dataSourceStore: dataSourceStore,
                modelContext: modelContext,
                conversationID: conversationID
            )
        } catch is CancellationError {
            finalActivityStatus = .failed
            finishCancelled(message: assistantMessage, conversation: conversation, modelContext: modelContext, conversationID: conversationID)
        } catch {
            finalActivityStatus = .failed
            finishWithError(
                message: assistantMessage,
                conversation: conversation,
                error: error,
                modelContext: modelContext,
                conversationID: conversationID
            )
        }
    }

    private func finishWithError(
        message: ChatMessage,
        conversation: Conversation,
        error: Error,
        modelContext: ModelContext,
        conversationID: UUID
    ) {
        message.isStreaming = false
        message.completedAt = .now
        message.errorMessage = ChatServiceError.userFacingMessage(for: error)
        message.isUnread = visibleConversationID != conversation.id
        conversation.updatedAt = .now
        try? modelContext.save()
        notifyCompletion(
            conversationID: conversationID,
            messageID: message.id,
            conversationTitle: conversation.isTemporary ? "Temporary Chat" : conversation.title,
            assistantMessage: message,
            modelContext: modelContext,
            error: error
        )
    }

    private func finishCancelled(
        message: ChatMessage,
        conversation: Conversation,
        modelContext: ModelContext,
        conversationID: UUID
    ) {
        message.isStreaming = false
        message.completedAt = .now
        message.isUnread = visibleConversationID != conversation.id
        conversation.updatedAt = .now
        try? modelContext.save()
        notify(event: .cancelled, conversationID: conversationID, messageID: message.id)
    }

    /// Builds the follow-up turns for a single silent continuation attempt
    /// after a mid-stream connection drop: the original turns, the partial
    /// reply already received (as if the model had said exactly that much),
    /// and an instruction to continue. This is a genuinely new request, not
    /// a re-send of the failed one — see `ChatServiceError.connectionDropped`.
    nonisolated static func continuationTurns(previousTurns: [ChatTurn], partialContent: String) -> [ChatTurn] {
        previousTurns + [
            ChatTurn(role: .assistant, content: partialContent),
            ChatTurn(
                role: .user,
                content: "Continue your previous response exactly where it left off. Do not repeat any earlier part of the reply."
            ),
        ]
    }

    private func applyPostStream(
        assistantMessage: ChatMessage,
        conversation: Conversation,
        skillCollector: SkillInvocationCollector,
        skillMatches: [SkillMatchable],
        skillsStore: SkillsStore,
        memoryStore: MemoryStore,
        rulesStore: RulesStore,
        dataSourceStore: AgentDataSourceStore,
        modelContext: ModelContext,
        conversationID: UUID
    ) async {
        assistantMessage.extractInlineImages()
        assistantMessage.isStreaming = false
        assistantMessage.completedAt = .now
        assistantMessage.isUnread = visibleConversationID != conversation.id

        captureCalendarProposals(from: assistantMessage, dataSourceStore: dataSourceStore)
        captureRemindersProposals(from: assistantMessage, dataSourceStore: dataSourceStore)
        captureContactsProposals(from: assistantMessage, dataSourceStore: dataSourceStore)
        captureMemoryProposals(from: assistantMessage, memoryStore: memoryStore, modelContext: modelContext, conversation: conversation)
        captureRuleProposals(from: assistantMessage, rulesStore: rulesStore, modelContext: modelContext, conversation: conversation)

        let invokedSkills = await skillCollector.invokedSkills
        for skill in invokedSkills {
            insertSkillSystemMessage(for: skill, conversation: conversation, modelContext: modelContext)
        }
        let skillProposals = await skillCollector.proposals
        captureSkillProposals(skillProposals, messageID: assistantMessage.id, skillsStore: skillsStore, modelContext: modelContext, conversation: conversation)

        conversation.updatedAt = .now
        try? modelContext.save()

        notifyCompletion(
            conversationID: conversationID,
            messageID: assistantMessage.id,
            conversationTitle: conversation.isTemporary ? "Temporary Chat" : conversation.title,
            assistantMessage: assistantMessage,
            modelContext: modelContext
        )
    }

    // MARK: - Helpers

    private func endBackgroundTask(_ id: UIBackgroundTaskIdentifier?) {
        guard let id, id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
    }

    /// Keeps the screen from auto-locking while any generation is in flight,
    /// so a long response isn't interrupted by idle sleep while the app is
    /// foregrounded. Does not affect a manual lock-button press or the app
    /// being backgrounded — only the OS idle timer.
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = !tasks.isEmpty
    }
}

// MARK: - Events

enum BackgroundGenerationEvent {
    case started
    case progress(elapsed: TimeInterval)
    case completed
    case cancelled
    case failed
}

extension Notification.Name {
    static let bgGenDidUpdate = Notification.Name("com.openchat.bgGenDidUpdate")
    static let bgGenCapturedCalendarProposals = Notification.Name("com.openchat.bgGenCapturedCalendarProposals")
    static let bgGenCapturedRemindersProposals = Notification.Name("com.openchat.bgGenCapturedRemindersProposals")
    static let bgGenCapturedContactsProposals = Notification.Name("com.openchat.bgGenCapturedContactsProposals")
    static let bgGenCapturedMemoryProposals = Notification.Name("com.openchat.bgGenCapturedMemoryProposals")
    static let bgGenCapturedRuleProposals = Notification.Name("com.openchat.bgGenCapturedRuleProposals")
    static let bgGenCapturedSkillProposals = Notification.Name("com.openchat.bgGenCapturedSkillProposals")
    static let bgGenMemorySaveFailed = Notification.Name("com.openchat.bgGenMemorySaveFailed")
    static let bgGenRuleSaveFailed = Notification.Name("com.openchat.bgGenRuleSaveFailed")
    static let bgGenSkillSaveFailed = Notification.Name("com.openchat.bgGenSkillSaveFailed")
}

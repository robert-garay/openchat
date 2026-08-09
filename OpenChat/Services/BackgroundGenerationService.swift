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
/// backgrounded.
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
    private var visibleConversationID: UUID?

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

    private struct BuildTurnsResult {
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
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "OpenChat generation \(conversationID)") { @MainActor [weak self] in
            // The system is about to suspend us; end the expired task and record
            // that it is no longer active so performGeneration's cleanup is safe.
            guard let self else { return }
            endBackgroundTask(backgroundTaskID)
            if var active = tasks[conversationID] {
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

        notify(event: .started, conversationID: conversationID, messageID: assistantMessage.id)
        return taskID
    }

    func cancelGeneration(for conversationID: UUID) {
        guard let active = tasks.removeValue(forKey: conversationID) else { return }
        active.task.cancel()
        endBackgroundTask(active.backgroundTaskID)
        Task {
            await LiveActivityService.shared.end(activityID: active.activityID, status: .failed)
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
        var finalActivityStatus: OpenChatLiveActivityAttributes.Status = .completed
        defer {
            Task { @MainActor in
                if let active = tasks[conversationID], active.taskID == taskID {
                    endBackgroundTask(active.backgroundTaskID)
                    tasks.removeValue(forKey: conversationID)
                }
            }
            Task {
                await LiveActivityService.shared.end(activityID: activityID, status: finalActivityStatus)
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

            try await runStream(
                client: client,
                modelID: modelID,
                baseURL: baseURL,
                apiKey: apiKey,
                turns: result.turns,
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

    private func buildTurns(
        conversation: Conversation,
        assistantMessage: ChatMessage,
        model: AIModel,
        provider: ConfiguredProvider,
        apiKey: String?,
        memoryStore: MemoryStore,
        rulesStore: RulesStore,
        dataSourceStore: AgentDataSourceStore,
        webSearchStore: WebSearchStore,
        skillsStore: SkillsStore,
        modelContext: ModelContext,
        effectiveEffortLevel: EffortLevel?,
        effectiveReasoningEnabled: Bool?
    ) async throws -> BuildTurnsResult {
        let supportsTools = model.supportsTools
        let supportsVision = model.supportsVision
        let supportsFiles = model.supportsFiles
        let skillToolsEnabled = skillsStore.isEnabled && supportsTools
        let skillMatches = fetchSkillMatches(using: skillsStore, modelContext: modelContext)
        let skillIndex = skillToolsEnabled ? SkillResolver.index(from: skillMatches) : nil

        let historyTurns = ConversationCompactionService.apiHistoryTurns(
            sortedMessages: conversation.sortedMessages,
            compactedSummary: conversation.compactedSummary.isEmpty ? nil : conversation.compactedSummary,
            compactedThroughMessageID: conversation.compactedThroughMessageID,
            includeImages: supportsVision,
            includeDocuments: supportsFiles,
            excludingMessageID: assistantMessage.id
        )
        let latestUserText = historyTurns.last(where: { $0.role == .user })?.content ?? ""

        let searchAPIKey = webSearchStore.activeAPIKey()
        let searchProviderName = webSearchStore.activeProviderDisplayName
        let searchClient = webSearchStore.makeActiveClient()
        let searchMode = WebSearchService.preferredMode(
            supportsTools: supportsTools,
            isActive: webSearchStore.isActive && !latestUserText.isEmpty
        )

        var middleSections: [String] = []

        if MemoryStore.shouldUseMemory(isTemporary: conversation.isTemporary, useInChats: memoryStore.useInChats) {
            let items = (try? memoryStore.fetchItems(modelContext: modelContext)) ?? []
            let injectionItems = memoryStore.injectionItems(from: items)
            if let memorySection = MemoryStore.contextSection(for: injectionItems) {
                middleSections.append(memorySection)
            }
            middleSections.append(MemoryStore.modelInstruction())
        }

        if RulesStore.shouldAllowRuleProposals(isTemporary: conversation.isTemporary, allowProposalsFromChat: rulesStore.allowProposalsFromChat) {
            let globalRuleItems = rulesStore.useGlobalRules
                ? [] : ((try? rulesStore.fetchItems(modelContext: modelContext)) ?? [])
            let chatRuleItems = rulesStore.useChatRules ? [] : conversation.rules
            let existingRuleItems = globalRuleItems + chatRuleItems
            if let rulesSection = RulesStore.contextSection(for: existingRuleItems) {
                middleSections.append(rulesSection)
            }
            middleSections.append(RulesStore.modelInstruction())
        }

        if let skillIndex, !skillIndex.isEmpty {
            middleSections.append(skillIndex)
        }

        dataSourceStore.refreshAuthorizationStatuses()
        if let agentContext = await AgentContextProvider(
            dataSourceStore: dataSourceStore,
            memoryItems: (try? memoryStore.fetchItems(modelContext: modelContext)) ?? []
        ).makeContextBlock() {
            middleSections.append(agentContext)
        }

        var tools: [ChatToolDefinition] = []
        var webSearchToolPrompt: String?
        if searchMode == .inject, let searchAPIKey, let searchClient, !latestUserText.isEmpty {
            do {
                let injected = try await WebSearchService.makeInjectedContext(
                    query: latestUserText,
                    apiKey: searchAPIKey,
                    client: searchClient
                )
                middleSections.append(injected)
            } catch {
                middleSections.append(
                    "Web search was enabled but failed: \(error.localizedDescription). Answer without live results."
                )
            }
        } else if searchMode == .toolCalling, searchAPIKey != nil, searchClient != nil {
            tools = [WebSearchService.toolDefinition(providerName: searchProviderName)]
            webSearchToolPrompt =
                "You have a web_search tool powered by \(searchProviderName). Use it when the user needs current or factual information from the web."
        }

        if skillToolsEnabled {
            tools.append(SkillToolService.invokeToolDefinition())
            tools.append(SkillToolService.createToolDefinition())
        }

        rulesStore.migrateLegacyGlobalRulesIfNeeded(modelContext: modelContext)

        let globalRulesText: String
        if rulesStore.useGlobalRules {
            let ruleItems = (try? rulesStore.fetchItems(modelContext: modelContext)) ?? []
            globalRulesText = RulesStore.injectionText(from: ruleItems)
        } else {
            globalRulesText = ""
        }
        let chatRulesText: String
        if rulesStore.useChatRules {
            let perChatRulesText = RulesStore.injectionText(from: conversation.rules)
            chatRulesText = [perChatRulesText, conversation.systemPrompt]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        } else {
            chatRulesText = ""
        }

        let systemContent = ChatSystemPromptBuilder.assemble(
            globalRules: globalRulesText,
            chatRules: chatRulesText,
            middleSections: middleSections,
            webSearchToolPrompt: webSearchToolPrompt
        )

        var turns: [ChatTurn] = []
        if let systemContent {
            turns.append(ChatTurn(role: .system, content: systemContent))
        }
        turns.append(contentsOf: historyTurns)

        let skillCollector = SkillInvocationCollector()
        let executeTool: @Sendable (ChatToolCall) async throws -> String = { call in
            switch call.name {
            case SkillToolService.invokeToolName:
                guard let slashName = SkillToolService.slashName(fromInvokeArguments: call.argumentsJSON),
                      let matched = skillMatches.first(where: { $0.slashName == SkillResolver.normalizeSlashName(slashName) })
                else {
                    return "No skill found with that slash name."
                }
                await skillCollector.recordInvoke(matched)
                return SkillResolver.systemBlock(for: matched)
            case SkillToolService.createToolName:
                guard let proposal = SkillToolService.proposal(fromCreateArguments: call.argumentsJSON) else {
                    return "Could not parse the skill draft — name, slash_name, and instructions must be non-empty."
                }
                await skillCollector.recordProposal(proposal)
                return "Draft captured. The user will review \"\(proposal.name)\" (/\(proposal.slashName)) before it's saved."
            default:
                guard let searchAPIKey, let searchClient else {
                    return "Search API key is not configured."
                }
                return try await WebSearchService.executeToolCall(
                    call,
                    apiKey: searchAPIKey,
                    client: searchClient
                )
            }
        }

        return BuildTurnsResult(
            turns: turns,
            tools: tools,
            executeTool: executeTool,
            skillCollector: skillCollector,
            skillMatches: skillMatches
        )
    }

    private func runStream(
        client: ChatCompletionClient,
        modelID: String,
        baseURL: String,
        apiKey: String?,
        turns: [ChatTurn],
        tools: [ChatToolDefinition],
        executeTool: @escaping @Sendable (ChatToolCall) async throws -> String,
        supportsImageGen: Bool,
        effort: EffortLevel?,
        reasoningEnabled: Bool?,
        assistantMessage: ChatMessage,
        activityID: String?,
        conversationID: UUID,
        startDate: Date
    ) async throws {
        var contentBuffer = ""
        var lastFlush = ContinuousClock().now
        let flushInterval: Duration = .milliseconds(80)
        var lastProgressNotify = ContinuousClock().now
        let progressNotifyInterval: Duration = .seconds(1)

        for try await event in client.streamReply(
            turns: turns,
            model: modelID,
            baseURL: baseURL,
            apiKey: apiKey,
            tools: tools,
            executeTool: executeTool,
            supportsImageGen: supportsImageGen,
            effort: effort,
            reasoningEnabled: reasoningEnabled
        ) {
            switch event {
            case .text(let delta):
                contentBuffer += delta
                let now = ContinuousClock().now
                if now >= lastFlush + flushInterval {
                    assistantMessage.content += contentBuffer
                    contentBuffer = ""
                    lastFlush = now
                }
                if now >= lastProgressNotify + progressNotifyInterval {
                    notifyProgress(
                        activityID: activityID,
                        conversationID: conversationID,
                        messageID: assistantMessage.id,
                        elapsed: Date().timeIntervalSince(startDate)
                    )
                    lastProgressNotify = now
                }
            case .images(let images):
                var existing = assistantMessage.imageAttachments
                existing.append(contentsOf: images)
                assistantMessage.imageAttachments = existing
            }
        }

        if !contentBuffer.isEmpty {
            assistantMessage.content += contentBuffer
        }
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
            assistantMessage: assistantMessage
        )
    }

    // MARK: - Completion handling

    private func notifyCompletion(
        conversationID: UUID,
        messageID: UUID,
        conversationTitle: String,
        assistantMessage: ChatMessage,
        error: Error? = nil
    ) {
        let didFail = error != nil || assistantMessage.errorMessage != nil
        notify(
            event: didFail ? .failed : .completed,
            conversationID: conversationID,
            messageID: messageID
        )

        // If the app is not active, post a local notification.
        if UIApplication.shared.applicationState != .active {
            Task {
                await NotificationService.shared.scheduleResponseNotification(
                    conversationID: conversationID,
                    conversationTitle: conversationTitle,
                    messagePreview: assistantMessage.content,
                    failed: didFail
                )
            }
        }
    }

    private func notifyProgress(activityID: String?, conversationID: UUID, messageID: UUID, elapsed: TimeInterval) {
        notify(event: .progress(elapsed: elapsed), conversationID: conversationID, messageID: messageID)
        Task {
            await LiveActivityService.shared.update(
                activityID: activityID,
                status: .generating(elapsed: elapsed)
            )
        }
    }

    // MARK: - Helpers

    private func endBackgroundTask(_ id: UIBackgroundTaskIdentifier?) {
        guard let id, id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
    }

    private func notify(event: BackgroundGenerationEvent, conversationID: UUID, messageID: UUID) {
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

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class ChatViewModel {
    private(set) var isStreaming = false
    var pendingAttachments: [ChatImageAttachment] = []
    var capabilityWarning: String?
    /// Non-vision model pick awaiting user confirmation when the thread (or composer) has images.
    private(set) var pendingModelSwitch: PendingModelSwitch?
    private(set) var pendingCalendarActionsByMessageID: [UUID: [CalendarActionProposal]] = [:]
    private(set) var calendarActionStatusByMessageID: [UUID: String] = [:]
    private(set) var isApplyingCalendarActions = false
    private(set) var pendingMemoryProposalsByMessageID: [UUID: [MemoryProposal]] = [:]
    private(set) var memoryActionStatusByMessageID: [UUID: String] = [:]
    private(set) var isCompacting = false
    private(set) var compactStatusMessage: String?

    struct PendingModelSwitch: Equatable {
        var providerID: String
        var modelID: String
        var modelDisplayName: String
        var clearsPendingAttachments: Bool
        var omitsThreadImages: Bool

        var message: String {
            var parts: [String] = []
            if omitsThreadImages {
                parts.append(
                    "\(modelDisplayName) can’t process images. Photos already in this chat stay visible but won’t be sent until you switch back to a vision model."
                )
            }
            if clearsPendingAttachments {
                parts.append("Unsent attachments will be removed.")
            }
            return parts.joined(separator: "\n\n")
        }
    }

    private let conversation: Conversation
    private let modelContext: ModelContext
    private let providerStore: ProviderStore
    private let dataSourceStore: AgentDataSourceStore
    private let webSearchStore: WebSearchStore
    private let rulesStore: RulesStore
    private let memoryStore: MemoryStore
    private var streamingTask: Task<Void, Never>?
    private var pendingSkillSystemBlock: String?
    private var titleGenerationTask: Task<Void, Never>?

    /// Per-chat override. When false, this conversation will not call search
    /// even if a provider is configured. Defaults on when search is active.
    var isWebSearchEnabledForChat: Bool

    init(
        conversation: Conversation,
        modelContext: ModelContext,
        providerStore: ProviderStore,
        dataSourceStore: AgentDataSourceStore,
        webSearchStore: WebSearchStore,
        rulesStore: RulesStore,
        memoryStore: MemoryStore
    ) {
        self.conversation = conversation
        self.modelContext = modelContext
        self.providerStore = providerStore
        self.dataSourceStore = dataSourceStore
        self.webSearchStore = webSearchStore
        self.rulesStore = rulesStore
        self.memoryStore = memoryStore
        self.isWebSearchEnabledForChat = webSearchStore.isActive
    }

    private var shouldUseMemory: Bool {
        MemoryStore.shouldUseMemory(isTemporary: conversation.isTemporary, useInChats: memoryStore.useInChats)
    }

    /// Search will run on the next send: chat toggle on + configured active provider ready.
    var isWebSearchArmed: Bool {
        isWebSearchEnabledForChat && webSearchStore.isActive
    }

    var webSearchProviderName: String {
        webSearchStore.activeProviderDisplayName
    }

    var selectedWebSearchProvider: WebSearchProviderKind? {
        isWebSearchArmed ? webSearchStore.activeProvider : nil
    }

    var webSearchStoreActiveLogo: String {
        webSearchStore.activeProvider.logoAssetName
    }

    var webSearchStoreActiveTint: String {
        webSearchStore.activeProvider.tintHex
    }

    var webSearchStoreActiveSymbol: String {
        webSearchStore.activeProvider.symbolName
    }

    /// Providers with a saved API key, shown in the composer picker.
    var configuredWebSearchProviders: [WebSearchProviderKind] {
        webSearchStore.configuredProviders
    }

    /// True when at least one search provider has a key (menu can open).
    var canUseWebSearch: Bool {
        webSearchStore.hasAnyAPIKey
    }

    func selectWebSearchProvider(_ kind: WebSearchProviderKind) {
        guard webSearchStore.hasAPIKey(for: kind) else { return }
        webSearchStore.setActiveProvider(kind)
        webSearchStore.setEnabled(true)
        isWebSearchEnabledForChat = true
        Haptics.light()
    }

    func disableWebSearchForChat() {
        isWebSearchEnabledForChat = false
        Haptics.light()
    }

    var currentProvider: ConfiguredProvider? {
        providerStore.provider(withID: conversation.providerID)
    }

    var currentModel: AIModel? {
        providerStore.model(providerID: conversation.providerID, modelID: conversation.modelID)
    }

    var supportsVision: Bool {
        currentModel?.supportsVision ?? false
    }

    func selectModel(providerID: String, modelID: String) {
        if providerID == conversation.providerID, modelID == conversation.modelID {
            return
        }

        let model = providerStore.model(providerID: providerID, modelID: modelID)
        let targetSupportsVision = model?.supportsVision == true
        let hasThreadImages = conversation.messages.contains { !$0.imageAttachments.isEmpty }
        let clearsPendingAttachments = !pendingAttachments.isEmpty && !targetSupportsVision
        let leavingVision = currentModel?.supportsVision == true

        let needsConfirmation = !targetSupportsVision
            && ((hasThreadImages && leavingVision) || clearsPendingAttachments)
        if needsConfirmation {
            pendingModelSwitch = PendingModelSwitch(
                providerID: providerID,
                modelID: modelID,
                modelDisplayName: model?.displayName ?? "This model",
                clearsPendingAttachments: clearsPendingAttachments,
                omitsThreadImages: hasThreadImages
            )
            return
        }

        applyModelSelection(providerID: providerID, modelID: modelID, clearPendingAttachments: clearsPendingAttachments)
    }

    func confirmPendingModelSwitch() {
        guard let pending = pendingModelSwitch else { return }
        pendingModelSwitch = nil
        applyModelSelection(
            providerID: pending.providerID,
            modelID: pending.modelID,
            clearPendingAttachments: pending.clearsPendingAttachments
        )
    }

    func cancelPendingModelSwitch() {
        pendingModelSwitch = nil
    }

    func dismissCapabilityWarning() {
        capabilityWarning = nil
    }

    func dismissCompactStatus() {
        compactStatusMessage = nil
    }

    var canShowCompact: Bool {
        CompactConversationSettings.isEnabled() && !conversation.isTemporary
    }

    var canCompactConversation: Bool {
        guard canShowCompact, !isStreaming, !isCompacting else { return false }
        let eligible = ConversationCompactionService.eligibleMessages(
            from: ConversationCompactionService.snapshots(from: conversation.sortedMessages)
        )
        return ConversationCompactionService.canCompact(messageCount: eligible.count)
    }

    func compactConversation() {
        guard canShowCompact, !isStreaming, !isCompacting else { return }
        guard let provider = currentProvider, let model = currentModel else { return }
        let apiKey = providerStore.apiKey(for: provider)
        guard !provider.requiresAPIKey || apiKey != nil else { return }

        let snapshots = ConversationCompactionService.snapshots(from: conversation.sortedMessages)
        guard let plan = ConversationCompactionService.planCompaction(
            sortedMessages: snapshots,
            compactedThroughMessageID: conversation.compactedThroughMessageID
        ) else {
            compactStatusMessage = "Not enough messages to compact."
            Haptics.warning()
            return
        }

        isCompacting = true
        let client = ChatService.client(for: provider.apiFormat)
        let baseURL = provider.baseURL
        let modelID = model.id
        let existingSummary = conversation.compactedSummary
        let transcript = ConversationCompactionService.transcriptForSummarization(
            existingSummary: existingSummary.isEmpty ? nil : existingSummary,
            messages: plan.messagesToSummarize
        )
        let summarizationTurns = [
            ChatTurn(role: .system, content: ConversationCompactionService.summarizationSystemPrompt()),
            ChatTurn(role: .user, content: ConversationCompactionService.summarizationUserPrompt(transcript: transcript))
        ]

        streamingTask = Task { [weak self] in
            guard let self else { return }
            do {
                var summary = ""
                for try await event in client.streamReply(
                    turns: summarizationTurns,
                    model: modelID,
                    baseURL: baseURL,
                    apiKey: apiKey
                ) {
                    if case .text(let delta) = event {
                        summary += delta
                    }
                }

                let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    compactStatusMessage = "Compaction failed: empty summary."
                    Haptics.warning()
                    isCompacting = false
                    return
                }

                conversation.compactedSummary = trimmed
                conversation.compactedThroughMessageID = plan.watermarkMessageID
                conversation.updatedAt = .now
                compactStatusMessage = "Conversation compacted."
                Haptics.success()
            } catch is CancellationError {
                compactStatusMessage = nil
            } catch {
                compactStatusMessage = "Compaction failed: \(error.localizedDescription)"
                Haptics.warning()
            }
            isCompacting = false
        }
    }

    private func applyModelSelection(providerID: String, modelID: String, clearPendingAttachments: Bool) {
        conversation.providerID = providerID
        conversation.modelID = modelID
        conversation.updatedAt = .now
        providerStore.recordModelUsage(providerID: providerID, modelID: modelID)
        if clearPendingAttachments {
            pendingAttachments = []
        }
    }

    func confirmCalendarActions(for messageID: UUID) {
        guard !isApplyingCalendarActions else { return }
        guard dataSourceStore.canEditCalendar else {
            calendarActionStatusByMessageID[messageID] = CalendarEventWriterError.editingDisabled.localizedDescription
            pendingCalendarActionsByMessageID[messageID] = nil
            return
        }
        guard let proposals = pendingCalendarActionsByMessageID[messageID], !proposals.isEmpty else { return }

        isApplyingCalendarActions = true
        var results: [String] = []
        for proposal in proposals {
            do {
                results.append(try CalendarEventWriter.apply(proposal))
            } catch {
                results.append(error.localizedDescription)
            }
        }
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

    func send(text: String) {
        let rawText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingAttachments
        guard (!rawText.isEmpty || !images.isEmpty), !isStreaming else { return }

        if !images.isEmpty, !supportsVision {
            capabilityWarning = ChatServiceError.modelLacksVision.errorDescription
            return
        }

        let skills = fetchSkillMatches()
        let resolution = SkillResolver.resolve(text: rawText, skills: skills)
        let resolvedText = resolution?.storedMessage ?? rawText
        pendingSkillSystemBlock = resolution.map { SkillResolver.systemBlock(for: $0.skill) }
        guard !resolvedText.isEmpty || !images.isEmpty || resolution != nil else {
            pendingSkillSystemBlock = nil
            return
        }

        pendingAttachments = []

        let userMessage = ChatMessage(role: .user, content: resolvedText, imageAttachments: images)
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)
        modelContext.insert(userMessage)
        conversation.updateDenormalizedPreview()

        let isFirstUserMessage = conversation.messages.filter { $0.role == .user }.count == 1
        if isFirstUserMessage, !conversation.isTemporary, !conversation.hasCustomTitle {
            let provisional = ConversationTitleGenerator.fallbackTitle(
                for: resolvedText,
                hasImages: !images.isEmpty
            )
            conversation.title = provisional
            if !resolvedText.isEmpty {
                requestTitleGeneration(from: resolvedText, provisionalTitle: provisional)
            }
        }
        conversation.updatedAt = .now

        requestAssistantReply()
    }

    private func fetchSkillMatches() -> [SkillMatchable] {
        let skills = (try? modelContext.fetch(FetchDescriptor<Skill>())) ?? []
        return skills.map(SkillMatchable.init(skill:))
    }

    private func requestTitleGeneration(from text: String, provisionalTitle: String) {
        guard let provider = currentProvider, let model = currentModel else { return }
        let apiKey = providerStore.apiKey(for: provider)
        guard !provider.requiresAPIKey || apiKey != nil else { return }

        let client = ChatService.client(for: provider.apiFormat)
        let baseURL = provider.baseURL
        let modelID = model.id
        let conversationID = conversation.id

        titleGenerationTask?.cancel()
        titleGenerationTask = Task { [weak self] in
            guard let self else { return }
            let generated = await ConversationTitleGenerator.generate(
                from: text,
                client: client,
                model: modelID,
                baseURL: baseURL,
                apiKey: apiKey
            )
            guard !Task.isCancelled, let generated else { return }
            guard conversation.id == conversationID,
                  !conversation.hasCustomTitle,
                  !conversation.isTemporary,
                  conversation.title == provisionalTitle
            else { return }
            conversation.title = generated
            conversation.updatedAt = .now
        }
    }

    func regenerateLastReply() {
        guard !isStreaming else { return }
        let sorted = conversation.sortedMessages
        guard let last = sorted.last, last.role == .assistant else { return }
        modelContext.delete(last)
        conversation.messages.removeAll { $0.id == last.id }
        requestAssistantReply()
    }

    func cancelStreaming() {
        streamingTask?.cancel()
    }

    private func requestAssistantReply() {
        guard let provider = currentProvider, let model = currentModel else { return }
        let apiKey = providerStore.apiKey(for: provider)
        guard !provider.requiresAPIKey || apiKey != nil else { return }

        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        assistantMessage.conversation = conversation
        conversation.messages.append(assistantMessage)
        modelContext.insert(assistantMessage)

        isStreaming = true
        let client = ChatService.client(for: provider.apiFormat)
        let baseURL = provider.baseURL
        let modelID = model.id
        let supportsTools = model.supportsTools
        let supportsVision = model.supportsVision
        let supportsImageGen = model.supportsImageGen
        let conversationSystemPrompt = conversation.systemPrompt
        let skillSystemBlock = pendingSkillSystemBlock
        pendingSkillSystemBlock = nil
        let historyTurns = ConversationCompactionService.apiHistoryTurns(
            sortedMessages: conversation.sortedMessages,
            compactedSummary: conversation.compactedSummary.isEmpty ? nil : conversation.compactedSummary,
            compactedThroughMessageID: conversation.compactedThroughMessageID,
            includeImages: supportsVision,
            excludingMessageID: assistantMessage.id
        )
        let latestUserText = historyTurns.last(where: { $0.role == .user })?.content ?? ""
        let searchAPIKey = webSearchStore.activeAPIKey()
        let searchProviderName = webSearchStore.activeProviderDisplayName
        let searchClient = webSearchStore.makeActiveClient()
        let searchMode = WebSearchService.preferredMode(
            supportsTools: supportsTools,
            isActive: isWebSearchEnabledForChat && webSearchStore.isActive
        )

        streamingTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Build context concurrently so the network request can start ASAP.
                async let memoryTask: String? = buildMemoryContext()
                async let agentContextTask: String? = buildAgentContext(skillSystemBlock: skillSystemBlock)
                async let searchTask: (injected: String?, toolPrompt: String?, tools: [ChatToolDefinition]) = buildSearchContext(
                    searchMode: searchMode,
                    searchAPIKey: searchAPIKey,
                    searchClient: searchClient,
                    latestUserText: latestUserText,
                    searchProviderName: searchProviderName
                )

                var middleSections: [String] = []
                if let memorySection = await memoryTask {
                    middleSections.append(memorySection)
                }
                if let agentSection = await agentContextTask {
                    middleSections.append(agentSection)
                }
                let searchResult = await searchTask
                if let injected = searchResult.injected {
                    middleSections.append(injected)
                }

                let systemContent = ChatSystemPromptBuilder.assemble(
                    globalRules: rulesStore.globalRules,
                    chatRules: conversationSystemPrompt,
                    middleSections: middleSections,
                    webSearchToolPrompt: searchResult.toolPrompt
                )

                var turns: [ChatTurn] = []
                if let systemContent {
                    turns.append(ChatTurn(role: .system, content: systemContent))
                }
                turns.append(contentsOf: historyTurns)

                let executeTool: @Sendable (ChatToolCall) async throws -> String = { call in
                    guard let searchAPIKey, let searchClient else {
                        return "Search API key is not configured."
                    }
                    return try await WebSearchService.executeToolCall(
                        call,
                        apiKey: searchAPIKey,
                        client: searchClient
                    )
                }

                // Coalesce deltas to avoid mutating SwiftData on every token.
                var contentBuffer = ""
                var lastFlush = ContinuousClock().now
                let flushInterval: Duration = .milliseconds(80)

                for try await event in client.streamReply(
                    turns: turns,
                    model: modelID,
                    baseURL: baseURL,
                    apiKey: apiKey,
                    tools: searchResult.tools,
                    executeTool: executeTool,
                    supportsImageGen: supportsImageGen
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
                    case .images(let images):
                        var existing = assistantMessage.imageAttachments
                        existing.append(contentsOf: images)
                        assistantMessage.imageAttachments = existing
                    }
                }

                // Flush any remaining buffered content.
                if !contentBuffer.isEmpty {
                    assistantMessage.content += contentBuffer
                }

                assistantMessage.isStreaming = false
                conversation.updateDenormalizedPreview()
                captureCalendarProposals(from: assistantMessage)
                captureMemoryProposals(from: assistantMessage)
            } catch is CancellationError {
                assistantMessage.isStreaming = false
                // Drop empty assistant bubbles so cancel never looks like a failure.
                if assistantMessage.content.isEmpty, assistantMessage.imageAttachments.isEmpty {
                    modelContext.delete(assistantMessage)
                    conversation.messages.removeAll { $0.id == assistantMessage.id }
                }
            } catch {
                assistantMessage.isStreaming = false
                assistantMessage.errorMessage = error.localizedDescription
            }
            conversation.updatedAt = .now
            isStreaming = false
            try? modelContext.save()
        }
    }

    private func buildMemoryContext() async -> String? {
        guard shouldUseMemory else { return nil }
        let items = (try? memoryStore.fetchItems(modelContext: modelContext)) ?? []
        let injectionItems = memoryStore.injectionItems(from: items)
        var parts: [String] = []
        if let memorySection = MemoryStore.contextSection(for: injectionItems) {
            parts.append(memorySection)
        }
        parts.append(MemoryStore.modelInstruction())
        return parts.joined(separator: "\n\n")
    }

    private func buildAgentContext(skillSystemBlock: String?) async -> String? {
        var sections: [String] = []
        if let skillSystemBlock, !skillSystemBlock.isEmpty {
            sections.append(skillSystemBlock)
        }
        dataSourceStore.refreshAuthorizationStatuses()
        if let agentContext = await AgentContextProvider(dataSourceStore: dataSourceStore).makeContextBlock() {
            sections.append(agentContext)
        }
        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n")
    }

    private func buildSearchContext(
        searchMode: WebSearchMode?,
        searchAPIKey: String?,
        searchClient: (any WebSearchClient)?,
        latestUserText: String,
        searchProviderName: String
    ) async -> (injected: String?, toolPrompt: String?, tools: [ChatToolDefinition]) {
        guard let searchMode else {
            return (nil, nil, [])
        }
        switch searchMode {
        case .inject:
            guard let searchAPIKey, let searchClient, !latestUserText.isEmpty else {
                return (nil, nil, [])
            }
            do {
                let injected = try await WebSearchService.makeInjectedContext(
                    query: latestUserText,
                    apiKey: searchAPIKey,
                    client: searchClient
                )
                return (injected, nil, [])
            } catch {
                let fallback = "Web search was enabled but failed: \(error.localizedDescription). Answer without live results."
                return (fallback, nil, [])
            }
        case .toolCalling:
            guard searchAPIKey != nil, searchClient != nil else {
                return (nil, nil, [])
            }
            let prompt = "You have a web_search tool powered by \(searchProviderName). Use it when the user needs current or factual information from the web."
            return (nil, prompt, [WebSearchService.toolDefinition(providerName: searchProviderName)])
        }
    }

    private func captureCalendarProposals(from message: ChatMessage) {
        guard dataSourceStore.canEditCalendar else { return }
        let proposals = CalendarActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        pendingCalendarActionsByMessageID[message.id] = proposals
    }

    private func captureMemoryProposals(from message: ChatMessage) {
        guard shouldUseMemory else { return }
        let proposals = MemoryActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        if memoryStore.requireConfirmation {
            pendingMemoryProposalsByMessageID[message.id] = proposals
        } else {
            saveMemoryProposals(proposals, source: .auto, messageID: message.id)
        }
    }

    private func saveMemoryProposals(_ proposals: [MemoryProposal], source: MemorySource, messageID: UUID) {
        var saved = 0
        for proposal in proposals {
            do {
                _ = try memoryStore.save(content: proposal.content, source: source, modelContext: modelContext)
                saved += 1
            } catch {
                memoryActionStatusByMessageID[messageID] = error.localizedDescription
                return
            }
        }
        if saved > 0 {
            try? modelContext.save()
            memoryActionStatusByMessageID[messageID] = "Memory updated."
        }
    }
}

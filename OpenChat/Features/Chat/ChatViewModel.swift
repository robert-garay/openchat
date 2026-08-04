import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class ChatViewModel {
    private(set) var isStreaming = false
    var composerText = ""
    var pendingAttachments: [ChatImageAttachment] = []
    var capabilityWarning: String?
    private(set) var pendingCalendarActionsByMessageID: [UUID: [CalendarActionProposal]] = [:]
    private(set) var calendarActionStatusByMessageID: [UUID: String] = [:]
    private(set) var isApplyingCalendarActions = false
    private(set) var isCompacting = false
    private(set) var compactStatusMessage: String?

    private let conversation: Conversation
    private let modelContext: ModelContext
    private let providerStore: ProviderStore
    private let dataSourceStore: AgentDataSourceStore
    private let webSearchStore: WebSearchStore
    private var streamingTask: Task<Void, Never>?

    /// Per-chat override. When false, this conversation will not call search
    /// even if a provider is configured. Defaults on when search is active.
    var isWebSearchEnabledForChat: Bool

    init(
        conversation: Conversation,
        modelContext: ModelContext,
        providerStore: ProviderStore,
        dataSourceStore: AgentDataSourceStore,
        webSearchStore: WebSearchStore
    ) {
        self.conversation = conversation
        self.modelContext = modelContext
        self.providerStore = providerStore
        self.dataSourceStore = dataSourceStore
        self.webSearchStore = webSearchStore
        self.isWebSearchEnabledForChat = webSearchStore.isActive
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
        conversation.providerID = providerID
        conversation.modelID = modelID
        conversation.updatedAt = .now

        let model = providerStore.model(providerID: providerID, modelID: modelID)
        if !pendingAttachments.isEmpty, model?.supportsVision != true {
            pendingAttachments = []
            capabilityWarning = "\(model?.displayName ?? "This model") can’t process images, so attached photos were removed."
        }
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
                for try await delta in client.streamReply(
                    turns: summarizationTurns,
                    model: modelID,
                    baseURL: baseURL,
                    apiKey: apiKey
                ) {
                    summary += delta
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

    func send() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingAttachments
        guard (!text.isEmpty || !images.isEmpty), !isStreaming else { return }

        if !images.isEmpty, !supportsVision {
            capabilityWarning = ChatServiceError.modelLacksVision.errorDescription
            return
        }

        composerText = ""
        pendingAttachments = []

        let userMessage = ChatMessage(role: .user, content: text, imageAttachments: images)
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)
        modelContext.insert(userMessage)

        if conversation.title == "New Chat" {
            if !text.isEmpty {
                conversation.title = String(text.prefix(40))
            } else {
                conversation.title = "Image"
            }
        }
        conversation.updatedAt = .now

        requestAssistantReply()
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

        let priorMessages = conversation.sortedMessages.filter { !($0.role == .assistant && $0.isStreaming) }

        if priorMessages.contains(where: { !$0.imageAttachments.isEmpty }), !model.supportsVision {
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: "",
                errorMessage: ChatServiceError.modelLacksVision.errorDescription
            )
            assistantMessage.conversation = conversation
            conversation.messages.append(assistantMessage)
            modelContext.insert(assistantMessage)
            conversation.updatedAt = .now
            return
        }

        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        assistantMessage.conversation = conversation
        conversation.messages.append(assistantMessage)
        modelContext.insert(assistantMessage)

        isStreaming = true
        let client = ChatService.client(for: provider.apiFormat)
        let baseURL = provider.baseURL
        let modelID = model.id
        let supportsTools = model.supportsTools
        let conversationSystemPrompt = conversation.systemPrompt
        let historyTurns: [ChatTurn] = ConversationCompactionService.apiHistoryTurns(
            sortedMessages: conversation.sortedMessages,
            compactedSummary: conversation.compactedSummary.isEmpty ? nil : conversation.compactedSummary,
            compactedThroughMessageID: conversation.compactedThroughMessageID,
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
                var systemParts: [String] = []
                if !conversationSystemPrompt.isEmpty {
                    systemParts.append(conversationSystemPrompt)
                }

                dataSourceStore.refreshAuthorizationStatuses()
                if let agentContext = await AgentContextProvider(dataSourceStore: dataSourceStore).makeContextBlock() {
                    systemParts.append(agentContext)
                }

                var tools: [ChatToolDefinition] = []
                if searchMode == .inject, let searchAPIKey, let searchClient, !latestUserText.isEmpty {
                    do {
                        let injected = try await WebSearchService.makeInjectedContext(
                            query: latestUserText,
                            apiKey: searchAPIKey,
                            client: searchClient
                        )
                        systemParts.append(injected)
                    } catch {
                        systemParts.append(
                            "Web search was enabled but failed: \(error.localizedDescription). Answer without live results."
                        )
                    }
                } else if searchMode == .toolCalling, searchAPIKey != nil, searchClient != nil {
                    tools = [WebSearchService.toolDefinition(providerName: searchProviderName)]
                    systemParts.append(
                        "You have a web_search tool powered by \(searchProviderName). Use it when the user needs current or factual information from the web."
                    )
                }

                var turns: [ChatTurn] = []
                if !systemParts.isEmpty {
                    turns.append(ChatTurn(role: .system, content: systemParts.joined(separator: "\n\n")))
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

                for try await delta in client.streamReply(
                    turns: turns,
                    model: modelID,
                    baseURL: baseURL,
                    apiKey: apiKey,
                    tools: tools,
                    executeTool: executeTool
                ) {
                    assistantMessage.content += delta
                }
                assistantMessage.isStreaming = false
                captureCalendarProposals(from: assistantMessage)
            } catch is CancellationError {
                assistantMessage.isStreaming = false
            } catch {
                assistantMessage.isStreaming = false
                assistantMessage.errorMessage = error.localizedDescription
            }
            conversation.updatedAt = .now
            isStreaming = false
        }
    }

    private func captureCalendarProposals(from message: ChatMessage) {
        guard dataSourceStore.canEditCalendar else { return }
        let proposals = CalendarActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        pendingCalendarActionsByMessageID[message.id] = proposals
    }
}

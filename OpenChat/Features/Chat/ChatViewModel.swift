import Foundation
import SwiftData
import Observation

// swiftlint:disable type_body_length file_length
@MainActor
@Observable
final class ChatViewModel {
    private(set) var isStreaming = false
    var composerText = ""
    var pendingAttachments: [ChatImageAttachment] = []
    var pendingDocumentAttachments: [ChatDocumentAttachment] = []
    var capabilityWarning: String?
    /// Non-vision model pick awaiting user confirmation when the thread (or composer) has images.
    private(set) var pendingModelSwitch: PendingModelSwitch?
    private(set) var pendingCalendarActionsByMessageID: [UUID: [CalendarActionProposal]] = [:]
    private(set) var calendarActionStatusByMessageID: [UUID: String] = [:]
    private(set) var isApplyingCalendarActions = false
    private(set) var pendingRemindersActionsByMessageID: [UUID: [RemindersActionProposal]] = [:]
    private(set) var remindersActionStatusByMessageID: [UUID: String] = [:]
    private(set) var isApplyingRemindersActions = false
    private(set) var pendingContactsActionsByMessageID: [UUID: [ContactsActionProposal]] = [:]
    private(set) var contactsActionStatusByMessageID: [UUID: String] = [:]
    private(set) var isApplyingContactsActions = false
    private(set) var pendingMemoryProposalsByMessageID: [UUID: [MemoryProposal]] = [:]
    private(set) var memoryActionStatusByMessageID: [UUID: String] = [:]
    private(set) var pendingSkillProposalsByMessageID: [UUID: [SkillProposal]] = [:]
    private(set) var skillActionStatusByMessageID: [UUID: String] = [:]
    private(set) var pendingRuleProposalsByMessageID: [UUID: [RuleProposal]] = [:]
    private(set) var ruleActionStatusByMessageID: [UUID: String] = [:]
    private(set) var isCompacting = false
    private(set) var compactStatusMessage: String?
    private(set) var editingMessageID: UUID?

    struct PendingModelSwitch: Equatable {
        var providerID: String
        var modelID: String
        var modelDisplayName: String
        var clearsPendingAttachments: Bool
        var omitsThreadImages: Bool
        var omitsThreadDocuments: Bool

        var message: String {
            var parts: [String] = []
            if omitsThreadImages {
                parts.append(
                    "\(modelDisplayName) can’t process images. Photos already in this chat stay visible but won’t be sent until you switch back to a vision model."
                )
            }
            if omitsThreadDocuments {
                parts.append(
                    "\(modelDisplayName) can't process documents. Documents already in this chat stay visible but won't be sent until you switch back to a file-capable model."
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
    private let skillsStore: SkillsStore
    private var streamingTask: Task<Void, Never>?
    private var titleGenerationTask: Task<Void, Never>?

    /// Per-chat override. When false, this conversation will not call search
    /// even if a provider is configured. Always starts off for a freshly
    /// opened chat; the user opts in per chat via the composer.
    var isWebSearchEnabledForChat: Bool
    /// Per-chat effort level.
    var effortLevel: EffortLevel
    /// Per-chat reasoning/thinking toggle. Used for models/providers that expose a
    /// separate thinking on/off parameter (e.g. OpenRouter `reasoning.enabled`).
    var isReasoningEnabled: Bool

    init(
        conversation: Conversation,
        modelContext: ModelContext,
        providerStore: ProviderStore,
        dataSourceStore: AgentDataSourceStore,
        webSearchStore: WebSearchStore,
        rulesStore: RulesStore,
        memoryStore: MemoryStore,
        skillsStore: SkillsStore
    ) {
        self.conversation = conversation
        self.modelContext = modelContext
        self.providerStore = providerStore
        self.dataSourceStore = dataSourceStore
        self.webSearchStore = webSearchStore
        self.rulesStore = rulesStore
        self.memoryStore = memoryStore
        self.skillsStore = skillsStore
        self.isWebSearchEnabledForChat = false
        self.effortLevel = conversation.effortLevel
        self.isReasoningEnabled = conversation.isReasoningEnabled
        restoreComposerState()
    }

    private func restoreComposerState() {
        composerText = conversation.draftMessage
        pendingAttachments = conversation.draftAttachments
        effortLevel = conversation.effortLevel
        isReasoningEnabled = conversation.isReasoningEnabled

        if let raw = conversation.lastUsedWebSearchProviderID,
           let kind = WebSearchProviderKind(rawValue: raw),
           webSearchStore.hasAPIKey(for: kind) {
            webSearchStore.setActiveProvider(kind)
            webSearchStore.setEnabled(true)
            isWebSearchEnabledForChat = true
        }
    }

    private var persistTask: Task<Void, Never>?

    func persistComposerState() {
        conversation.draftMessage = composerText
        conversation.draftAttachments = pendingAttachments
        conversation.lastUsedWebSearchProviderID = isWebSearchEnabledForChat ? webSearchStore.activeProvider.rawValue : nil
        conversation.effortLevel = effortLevel
        conversation.isReasoningEnabled = isReasoningEnabled

        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            try? modelContext.save()
        }
    }

    private var shouldUseMemory: Bool {
        MemoryStore.shouldUseMemory(isTemporary: conversation.isTemporary, useInChats: memoryStore.useInChats)
    }

    private var shouldAllowRuleProposals: Bool {
        RulesStore.shouldAllowRuleProposals(
            isTemporary: conversation.isTemporary,
            allowProposalsFromChat: rulesStore.allowProposalsFromChat
        )
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

    /// True when web search is enabled in Settings and at least one provider has a key.
    var canUseWebSearch: Bool {
        webSearchStore.isEnabled && webSearchStore.hasAnyAPIKey
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

    /// Provider branding for a message bubble. Assistant turns keep the provider that generated them.
    func provider(for message: ChatMessage) -> ConfiguredProvider? {
        guard message.role == .assistant else { return nil }
        let id = message.providerID ?? conversation.providerID
        return providerStore.provider(withID: id)
    }

    var supportsVision: Bool {
        currentModel?.supportsVision ?? false
    }

    var supportsFiles: Bool {
        currentModel?.supportsFiles ?? false
    }

    var supportsEffort: Bool {
        currentModel?.supportsEffort ?? false
    }

    func setEffortLevel(_ level: EffortLevel) {
        effortLevel = level
        conversation.effortLevel = level
        if hasSeparateThinkingToggle, !isReasoningEnabled {
            isReasoningEnabled = true
            conversation.isReasoningEnabled = true
        }
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            try? modelContext.save()
        }
        Haptics.light()
    }

    func selectModel(providerID: String, modelID: String) {
        if providerID == conversation.providerID, modelID == conversation.modelID {
            return
        }

        let model = providerStore.model(providerID: providerID, modelID: modelID)
        let targetSupportsVision = model?.supportsVision == true
        let targetSupportsFiles = model?.supportsFiles == true
        let hasThreadImages = conversation.messages.contains { !$0.imageAttachments.isEmpty }
        let hasThreadDocuments = conversation.messages.contains { !$0.documentAttachments.isEmpty }
        let clearsPendingAttachments = (!pendingAttachments.isEmpty && !targetSupportsVision)
            || (!pendingDocumentAttachments.isEmpty && !targetSupportsFiles)
        let leavingVision = currentModel?.supportsVision == true
        let leavingFiles = currentModel?.supportsFiles == true

        let omitsThreadImages = !targetSupportsVision && hasThreadImages && leavingVision
        let omitsThreadDocuments = !targetSupportsFiles && hasThreadDocuments && leavingFiles

        let needsConfirmation = omitsThreadImages || omitsThreadDocuments || clearsPendingAttachments
        if needsConfirmation {
            pendingModelSwitch = PendingModelSwitch(
                providerID: providerID,
                modelID: modelID,
                modelDisplayName: model?.displayName ?? "This model",
                clearsPendingAttachments: clearsPendingAttachments,
                omitsThreadImages: omitsThreadImages,
                omitsThreadDocuments: omitsThreadDocuments
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
                    apiKey: apiKey,
                    effort: supportsEffort ? effectiveEffortLevel : nil,
                    reasoningEnabled: nil
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
            pendingDocumentAttachments = []
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

    func confirmRemindersActions(for messageID: UUID) {
        guard !isApplyingRemindersActions else { return }
        guard dataSourceStore.canEditReminders else {
            remindersActionStatusByMessageID[messageID] = RemindersWriterError.editingDisabled.localizedDescription
            pendingRemindersActionsByMessageID[messageID] = nil
            return
        }
        guard let proposals = pendingRemindersActionsByMessageID[messageID], !proposals.isEmpty else { return }

        isApplyingRemindersActions = true
        var results: [String] = []
        for proposal in proposals {
            do {
                results.append(try RemindersWriter.apply(proposal))
            } catch {
                results.append(error.localizedDescription)
            }
        }
        remindersActionStatusByMessageID[messageID] = results.joined(separator: "\n")
        pendingRemindersActionsByMessageID[messageID] = nil
        isApplyingRemindersActions = false
        Haptics.success()
    }

    func dismissRemindersActions(for messageID: UUID) {
        pendingRemindersActionsByMessageID[messageID] = nil
        remindersActionStatusByMessageID[messageID] = "Reminders changes discarded."
        Haptics.light()
    }

    func confirmContactsActions(for messageID: UUID) {
        guard !isApplyingContactsActions else { return }
        guard dataSourceStore.canEditContacts else {
            contactsActionStatusByMessageID[messageID] = ContactsWriterError.editingDisabled.localizedDescription
            pendingContactsActionsByMessageID[messageID] = nil
            return
        }
        guard let proposals = pendingContactsActionsByMessageID[messageID], !proposals.isEmpty else { return }

        isApplyingContactsActions = true
        var results: [String] = []
        for proposal in proposals {
            do {
                results.append(try ContactsWriter.apply(proposal))
            } catch {
                results.append(error.localizedDescription)
            }
        }
        contactsActionStatusByMessageID[messageID] = results.joined(separator: "\n")
        pendingContactsActionsByMessageID[messageID] = nil
        isApplyingContactsActions = false
        Haptics.success()
    }

    func dismissContactsActions(for messageID: UUID) {
        pendingContactsActionsByMessageID[messageID] = nil
        contactsActionStatusByMessageID[messageID] = "Contacts changes discarded."
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

    /// Clears a pending skill proposal after the user saved it via the review sheet
    /// (SkillEditorView performs the actual save; this only clears the bookkeeping).
    func clearSkillProposalAfterReview(for messageID: UUID) {
        pendingSkillProposalsByMessageID[messageID] = nil
        skillActionStatusByMessageID[messageID] = "Skill saved."
        Haptics.success()
    }

    func dismissSkillProposals(for messageID: UUID) {
        pendingSkillProposalsByMessageID[messageID] = nil
        skillActionStatusByMessageID[messageID] = "Skill discarded."
        Haptics.light()
    }

    /// Clears a pending rule proposal after the user saved it via the review sheet
    /// (RuleReviewSheet performs the actual save; this only clears the bookkeeping).
    /// Removes only the reviewed proposal — any remaining proposals for this message stay pending.
    func clearRuleProposalAfterReview(for messageID: UUID, proposalID: UUID) {
        guard var proposals = pendingRuleProposalsByMessageID[messageID] else { return }
        proposals.removeAll { $0.id == proposalID }
        if proposals.isEmpty {
            pendingRuleProposalsByMessageID[messageID] = nil
            ruleActionStatusByMessageID[messageID] = "Rule saved."
        } else {
            pendingRuleProposalsByMessageID[messageID] = proposals
        }
        Haptics.success()
    }

    func dismissRuleProposals(for messageID: UUID) {
        pendingRuleProposalsByMessageID[messageID] = nil
        ruleActionStatusByMessageID[messageID] = "Rule discarded."
        Haptics.light()
    }

    func send() {
        let rawText = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingAttachments
        let documents = pendingDocumentAttachments
        guard (!rawText.isEmpty || !images.isEmpty || !documents.isEmpty), !isStreaming else { return }

        if !images.isEmpty, !supportsVision {
            capabilityWarning = ChatServiceError.modelLacksVision.errorDescription
            return
        }
        if !documents.isEmpty, !supportsFiles {
            capabilityWarning = ChatServiceError.modelLacksFiles.errorDescription
            return
        }

        let skills = fetchSkillMatches()
        let resolution = SkillResolver.resolve(text: rawText, skills: skills)
        let text = resolution?.storedMessage ?? rawText
        guard !text.isEmpty || !images.isEmpty || !documents.isEmpty else { return }

        composerText = ""
        pendingAttachments = []
        pendingDocumentAttachments = []
        conversation.draftMessage = ""
        conversation.draftAttachments = []
        conversation.lastUsedWebSearchProviderID = nil

        // Explicit /slash-name invocation pins its instructions into the conversation
        // immediately, synchronously, before the user's message — same-turn, same as
        // an auto-invoked skill lands next-turn once persisted by requestAssistantReply().
        if let resolution {
            insertSkillSystemMessage(for: resolution.skill)
        }

        let userMessage = ChatMessage(role: .user, content: text, imageAttachments: images, documentAttachments: documents)
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)
        modelContext.insert(userMessage)

        let isFirstUserMessage = conversation.messages.filter { $0.role == .user }.count == 1
        if isFirstUserMessage, !conversation.isTemporary, !conversation.hasCustomTitle {
            let provisional = ConversationTitleGenerator.fallbackTitle(
                for: text,
                hasImages: !images.isEmpty
            )
            conversation.title = provisional
            if !text.isEmpty {
                requestTitleGeneration(from: text, provisionalTitle: provisional)
            }
        }
        conversation.updatedAt = .now

        requestAssistantReply()
    }

    /// Empty when the Skills feature is off — callers never need a separate enabled check.
    private func fetchSkillMatches() -> [SkillMatchable] {
        guard skillsStore.isEnabled else { return [] }
        let skills = (try? modelContext.fetch(FetchDescriptor<Skill>())) ?? []
        return SkillResolver.withBuiltIns(skills.map(SkillMatchable.init(skill:)))
    }

    private func insertSkillSystemMessage(for skill: SkillMatchable) {
        let message = ChatMessage(role: .system, content: SkillResolver.systemBlock(for: skill))
        message.conversation = conversation
        conversation.messages.append(message)
        modelContext.insert(message)
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

    /// The message being edited, for the edit screen's `fullScreenCover(item:)`.
    var editingMessage: ChatMessage? {
        guard let editingMessageID else { return nil }
        return conversation.messages.first { $0.id == editingMessageID }
    }

    func beginEditing(_ message: ChatMessage) {
        guard !isStreaming, message.role == .user else { return }
        editingMessageID = message.id
    }

    func cancelEditing() {
        editingMessageID = nil
    }

    /// Applies an edit and regenerates from it. Returns `false` without mutating
    /// anything when a guard rejects the edit, so the edit screen can stay up
    /// with the user's text intact rather than silently discarding it.
    @discardableResult
    func saveEdit(_ message: ChatMessage, newText: String, attachments: [ChatImageAttachment]) -> Bool {
        guard editingMessageID == message.id, !isStreaming else { return false }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty || !message.documentAttachments.isEmpty else { return false }
        guard let provider = currentProvider, currentModel != nil else { return false }
        let apiKey = providerStore.apiKey(for: provider)
        guard !provider.requiresAPIKey || apiKey != nil else { return false }

        // Mirrors send(): the model can be switched after the edit screen opens.
        if !attachments.isEmpty, !supportsVision {
            capabilityWarning = ChatServiceError.modelLacksVision.errorDescription
            return false
        }

        message.content = trimmed
        message.imageAttachments = attachments

        let trailingMessages = conversation.messages(after: message)
        let trailingIDs = Set(trailingMessages.map(\.id))
        for trailing in trailingMessages {
            modelContext.delete(trailing)
        }
        conversation.messages.removeAll { trailingIDs.contains($0.id) }

        if let watermark = conversation.compactedThroughMessageID,
           trailingIDs.contains(watermark) {
            conversation.compactedThroughMessageID = nil
            conversation.compactedSummary = ""
        }

        conversation.updatedAt = .now
        editingMessageID = nil

        requestAssistantReply()
        return true
    }

    func cancelStreaming() {
        streamingTask?.cancel()
    }

    private func requestAssistantReply() {
        guard let provider = currentProvider, let model = currentModel else { return }
        let apiKey = providerStore.apiKey(for: provider)
        guard !provider.requiresAPIKey || apiKey != nil else { return }

        let assistantMessage = ChatMessage(
            role: .assistant,
            content: "",
            isStreaming: true,
            providerID: provider.id,
            modelID: model.id
        )
        assistantMessage.conversation = conversation
        conversation.messages.append(assistantMessage)
        modelContext.insert(assistantMessage)

        isStreaming = true
        let client = ChatService.client(for: provider.apiFormat)
        let baseURL = provider.baseURL
        let modelID = model.id
        let supportsTools = model.supportsTools
        let supportsVision = model.supportsVision
        let supportsFiles = model.supportsFiles
        let supportsImageGen = model.supportsImageGen
        let conversationSystemPrompt = conversation.systemPrompt
        let skillMatches = fetchSkillMatches()
        let skillToolsEnabled = skillsStore.isEnabled && supportsTools
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
            isActive: isWebSearchEnabledForChat && webSearchStore.isActive
        )

        streamingTask = Task { [weak self] in
            guard let self else { return }
            await performAssistantReplyStream(
                assistantMessage: assistantMessage,
                client: client,
                baseURL: baseURL,
                modelID: modelID,
                supportsImageGen: supportsImageGen,
                conversationSystemPrompt: conversationSystemPrompt,
                skillMatches: skillMatches,
                skillToolsEnabled: skillToolsEnabled,
                skillIndex: skillIndex,
                historyTurns: historyTurns,
                latestUserText: latestUserText,
                searchAPIKey: searchAPIKey,
                searchProviderName: searchProviderName,
                searchClient: searchClient,
                searchMode: searchMode,
                apiKey: apiKey
            )
        }
    }

    private func performAssistantReplyStream(
        assistantMessage: ChatMessage,
        client: ChatCompletionClient,
        baseURL: String,
        modelID: String,
        supportsImageGen: Bool,
        conversationSystemPrompt: String,
        skillMatches: [SkillMatchable],
        skillToolsEnabled: Bool,
        skillIndex: String?,
        historyTurns: [ChatTurn],
        latestUserText: String,
        searchAPIKey: String?,
        searchProviderName: String,
        searchClient: (any WebSearchClient)?,
        searchMode: WebSearchMode?,
        apiKey: String?
    ) async {
        do {
            var middleSections: [String] = []

            if shouldUseMemory {
                let items = (try? memoryStore.fetchItems(modelContext: modelContext)) ?? []
                let injectionItems = memoryStore.injectionItems(from: items)
                if let memorySection = MemoryStore.contextSection(for: injectionItems) {
                    middleSections.append(memorySection)
                }
                middleSections.append(MemoryStore.modelInstruction())
            }

            if shouldAllowRuleProposals {
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
            if let agentContext = await AgentContextProvider(dataSourceStore: dataSourceStore).makeContextBlock() {
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
                chatRulesText = [perChatRulesText, conversationSystemPrompt]
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

            // Coalesce deltas so we don't mutate SwiftData / redraw the message view on every token.
            var contentBuffer = ""
            var lastFlush = ContinuousClock().now
            let flushInterval: Duration = .milliseconds(80)

            for try await event in client.streamReply(
                turns: turns,
                model: modelID,
                baseURL: baseURL,
                apiKey: apiKey,
                tools: tools,
                executeTool: executeTool,
                supportsImageGen: supportsImageGen,
                effort: (supportsEffort && (!hasSeparateThinkingToggle || isReasoningEnabled)) ? effectiveEffortLevel : nil,
                reasoningEnabled: hasSeparateThinkingToggle ? effectiveReasoningEnabled : nil
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
            assistantMessage.completedAt = .now
            captureCalendarProposals(from: assistantMessage)
            captureRemindersProposals(from: assistantMessage)
            captureContactsProposals(from: assistantMessage)
            captureMemoryProposals(from: assistantMessage)
            captureRuleProposals(from: assistantMessage)
            let invokedSkills = await skillCollector.invokedSkills
            for skill in invokedSkills {
                insertSkillSystemMessage(for: skill)
            }
            let skillProposals = await skillCollector.proposals
            captureSkillProposals(skillProposals, messageID: assistantMessage.id)
        } catch is CancellationError {
            assistantMessage.isStreaming = false
            assistantMessage.completedAt = .now
        } catch {
            assistantMessage.isStreaming = false
            assistantMessage.completedAt = .now
            assistantMessage.errorMessage = ChatServiceError.userFacingMessage(for: error)
        }
        conversation.updatedAt = .now
        isStreaming = false
    }

    private func captureCalendarProposals(from message: ChatMessage) {
        guard dataSourceStore.canEditCalendar else { return }
        let proposals = CalendarActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        pendingCalendarActionsByMessageID[message.id] = proposals
    }

    private func captureRemindersProposals(from message: ChatMessage) {
        guard dataSourceStore.canEditReminders else { return }
        let proposals = RemindersActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        pendingRemindersActionsByMessageID[message.id] = proposals
    }

    private func captureContactsProposals(from message: ChatMessage) {
        guard dataSourceStore.canEditContacts else { return }
        let proposals = ContactsActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        pendingContactsActionsByMessageID[message.id] = proposals
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

    private func captureRuleProposals(from message: ChatMessage) {
        guard shouldAllowRuleProposals else { return }
        let proposals = RuleActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        if rulesStore.requireConfirmation {
            pendingRuleProposalsByMessageID[message.id] = proposals
        } else {
            saveRuleProposals(proposals, messageID: message.id)
        }
    }

    private func saveRuleProposals(_ proposals: [RuleProposal], messageID: UUID) {
        var saved = 0
        for proposal in proposals {
            do {
                _ = try rulesStore.save(
                    content: proposal.content,
                    modelContext: modelContext,
                    conversation: proposal.scope == .global ? nil : conversation
                )
                saved += 1
            } catch {
                ruleActionStatusByMessageID[messageID] = error.localizedDescription
                return
            }
        }
        if saved > 0 {
            try? modelContext.save()
            ruleActionStatusByMessageID[messageID] = "Rule saved."
        }
    }

    private func captureSkillProposals(_ proposals: [SkillProposal], messageID: UUID) {
        guard !proposals.isEmpty else { return }
        if skillsStore.requireConfirmation {
            pendingSkillProposalsByMessageID[messageID] = proposals
        } else {
            saveSkillProposals(proposals, messageID: messageID)
        }
    }

    private func saveSkillProposals(_ proposals: [SkillProposal], messageID: UUID) {
        var saved = 0
        for proposal in proposals {
            do {
                _ = try skillsStore.save(
                    name: proposal.name,
                    slashName: proposal.slashName,
                    skillDescription: proposal.description,
                    instructions: proposal.instructions,
                    createdFromChatID: conversation.id,
                    modelContext: modelContext
                )
                saved += 1
            } catch {
                skillActionStatusByMessageID[messageID] = error.localizedDescription
                return
            }
        }
        if saved > 0 {
            try? modelContext.save()
            skillActionStatusByMessageID[messageID] = "Skill saved."
        }
    }
}

// swiftlint:enable type_body_length

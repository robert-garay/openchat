import Foundation
import SwiftData
import Observation

// swiftlint:disable type_body_length file_length
@MainActor
@Observable
final class ChatViewModel {
    var isStreaming = false
    var composerText = ""
    var pendingAttachments: [ChatImageAttachment] = []
    var pendingDocumentAttachments: [ChatDocumentAttachment] = []
    var capabilityWarning: String?
    /// Non-vision model pick awaiting user confirmation when the thread (or composer) has images.
    private(set) var pendingModelSwitch: PendingModelSwitch?
    var pendingCalendarActionsByMessageID: [UUID: [CalendarActionProposal]] = [:]
    var calendarActionStatusByMessageID: [UUID: String] = [:]
    var isApplyingCalendarActions = false
    var pendingRemindersActionsByMessageID: [UUID: [RemindersActionProposal]] = [:]
    var remindersActionStatusByMessageID: [UUID: String] = [:]
    var isApplyingRemindersActions = false
    var pendingContactsActionsByMessageID: [UUID: [ContactsActionProposal]] = [:]
    var contactsActionStatusByMessageID: [UUID: String] = [:]
    var isApplyingContactsActions = false
    var pendingMemoryProposalsByMessageID: [UUID: [MemoryProposal]] = [:]
    var memoryActionStatusByMessageID: [UUID: String] = [:]
    var pendingSkillProposalsByMessageID: [UUID: [SkillProposal]] = [:]
    var skillActionStatusByMessageID: [UUID: String] = [:]
    var pendingRuleProposalsByMessageID: [UUID: [RuleProposal]] = [:]
    var ruleActionStatusByMessageID: [UUID: String] = [:]
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

    internal let conversation: Conversation
    internal let modelContext: ModelContext
    private let providerStore: ProviderStore
    internal let dataSourceStore: AgentDataSourceStore
    private let webSearchStore: WebSearchStore
    internal let rulesStore: RulesStore
    internal let memoryStore: MemoryStore
    internal let skillsStore: SkillsStore
    private let voiceModeStore: VoiceModeStore
    private var titleGenerationTask: Task<Void, Never>?
    private var compactionTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) var generationObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) var calendarProposalObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) var remindersProposalObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) var contactsProposalObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) var memoryProposalObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) var ruleProposalObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) var skillProposalObserver: NSObjectProtocol?

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
        skillsStore: SkillsStore,
        voiceModeStore: VoiceModeStore
    ) {
        self.conversation = conversation
        self.modelContext = modelContext
        self.providerStore = providerStore
        self.dataSourceStore = dataSourceStore
        self.webSearchStore = webSearchStore
        self.rulesStore = rulesStore
        self.memoryStore = memoryStore
        self.skillsStore = skillsStore
        self.voiceModeStore = voiceModeStore
        self.isWebSearchEnabledForChat = false
        self.effortLevel = conversation.effortLevel
        self.isReasoningEnabled = conversation.isReasoningEnabled
        restoreComposerState()
        self.isStreaming = BackgroundGenerationService.shared.isGenerating(for: conversation.id)
        setupGenerationObserver()
        refreshPendingProposals()
    }

    deinit {
        [
            generationObserver,
            calendarProposalObserver,
            remindersProposalObserver,
            contactsProposalObserver,
            memoryProposalObserver,
            ruleProposalObserver,
            skillProposalObserver
        ]
        .compactMap { $0 }
        .forEach(NotificationCenter.default.removeObserver)
    }

    // Generation observer, proposal refresh, and related helpers live in
    // ChatViewModel+BackgroundGeneration.swift.

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

    internal var shouldUseMemory: Bool {
        MemoryStore.shouldUseMemory(isTemporary: conversation.isTemporary, useInChats: memoryStore.useInChats)
    }

    internal var shouldAllowRuleProposals: Bool {
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

    /// Voice mode always talks to OpenAI's Realtime API using the model/voice
    /// configured in Settings — independent of this chat's own selected
    /// provider/model, same as web search or skills being available everywhere
    /// once turned on. Gated on the feature being enabled and an OpenAI key existing.
    var canUseVoiceMode: Bool {
        guard voiceModeStore.isEnabled,
              !voiceModeStore.modelID.isEmpty,
              let openAI = providerStore.provider(withID: "openai") else { return false }
        return providerStore.apiKey(for: openAI) != nil
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

        compactionTask = Task { [weak self] in
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

    // Proposal action/capture helpers live in ChatViewModel+Proposals.swift.

    func send() {
        let rawText = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingAttachments
        let documents = pendingDocumentAttachments
        guard !rawText.isEmpty || !images.isEmpty || !documents.isEmpty, !isStreaming else { return }

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

    private func requestAssistantReply() {
        let provider = currentProvider
        let model = currentModel
        let apiKey = provider.flatMap { providerStore.apiKey(for: $0) }
        let immediateError: Error? = if provider == nil || model == nil {
            ChatServiceError.providerOrModelNotFound
        } else if provider?.requiresAPIKey == true && apiKey == nil {
            ChatServiceError.missingAPIKey
        } else {
            nil
        }

        let assistantMessage = ChatMessage(
            role: .assistant,
            content: "",
            isStreaming: true,
            providerID: provider?.id ?? conversation.providerID,
            modelID: model?.id ?? conversation.modelID
        )
        assistantMessage.conversation = conversation
        conversation.messages.append(assistantMessage)
        modelContext.insert(assistantMessage)

        if let immediateError {
            assistantMessage.isStreaming = false
            assistantMessage.completedAt = .now
            assistantMessage.errorMessage = ChatServiceError.userFacingMessage(for: immediateError)
            conversation.updatedAt = .now
            try? modelContext.save()
            return
        }

        try? modelContext.save()

        isStreaming = true
        requestNotificationAuthorizationIfNeeded()
        BackgroundGenerationService.shared.startGeneration(
            for: assistantMessage,
            in: conversation,
            using: modelContext
        )
    }

    // Background-generation helpers live in ChatViewModel+BackgroundGeneration.swift.
}

// swiftlint:enable type_body_length

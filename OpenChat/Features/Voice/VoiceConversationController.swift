import Foundation
import SwiftData
import Observation

/// View-facing coordinator for one voice-mode call. Owns a `RealtimeVoiceSession`
/// + `VoiceAudioEngine` pair, turns realtime events into `ChatMessage`s in the
/// current `Conversation`, and dispatches function calls to the same tool
/// services text chat uses (web search, skills).
@MainActor
@Observable
final class VoiceConversationController {
    enum ConnectionState: Equatable {
        case idle
        case connecting
        case listening
        case userSpeaking
        case assistantSpeaking
        case runningTool(String)
        case reconnecting
        case ended
        case failed(String)
    }

    static let model = "gpt-4o-realtime-preview"

    private(set) var state: ConnectionState = .idle
    private(set) var partialUserTranscript = ""
    private(set) var partialAssistantTranscript = ""
    private(set) var inputLevel: Float = 0
    private(set) var outputLevel: Float = 0
    private(set) var isMuted = false

    private let conversation: Conversation
    private let modelContext: ModelContext
    private let providerStore: ProviderStore
    private let webSearchStore: WebSearchStore
    private let skillsStore: SkillsStore
    private let rulesStore: RulesStore
    private let memoryStore: MemoryStore

    private let session: RealtimeVoiceSession
    private let audioEngine: any VoiceAudioEngineProtocol

    private var eventTask: Task<Void, Never>?
    private var audioForwardingTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var pendingFunctionCalls: [String: String] = [:]
    private var hasAttemptedReconnect = false
    private let skillCollector = SkillInvocationCollector()
    private var toolContext: (tools: [ChatToolDefinition], execute: @Sendable (ChatToolCall) async throws -> String) = ([], { _ in "" })
    private let voice: String

    init(
        conversation: Conversation,
        modelContext: ModelContext,
        providerStore: ProviderStore,
        webSearchStore: WebSearchStore,
        skillsStore: SkillsStore,
        rulesStore: RulesStore,
        memoryStore: MemoryStore,
        voice: String = RealtimeVoiceOption.alloy.rawValue,
        session: RealtimeVoiceSession = RealtimeVoiceSession(),
        audioEngine: any VoiceAudioEngineProtocol = VoiceAudioEngine()
    ) {
        self.conversation = conversation
        self.modelContext = modelContext
        self.providerStore = providerStore
        self.webSearchStore = webSearchStore
        self.skillsStore = skillsStore
        self.rulesStore = rulesStore
        self.memoryStore = memoryStore
        self.voice = voice
        self.session = session
        self.audioEngine = audioEngine
    }

    /// Checked before presenting voice mode at all — surfaced as an inline
    /// composer error rather than a failed connection after the screen opens.
    var missingAPIKeyMessage: String? {
        guard let provider = providerStore.provider(withID: "openai"),
              providerStore.apiKey(for: provider) != nil else {
            return "Add an OpenAI API key in Settings to use voice mode."
        }
        return nil
    }

    func start() async {
        guard state == .idle else { return }
        guard let provider = providerStore.provider(withID: "openai"),
              let apiKey = providerStore.apiKey(for: provider) else {
            state = .failed(missingAPIKeyMessage ?? "OpenAI isn't configured.")
            return
        }

        state = .connecting
        toolContext = buildToolContext()

        do {
            try await audioEngine.start()
        } catch {
            state = .failed(RealtimeVoiceError.audioEngineUnavailable.localizedDescription)
            return
        }

        await connectSession(apiKey: apiKey)
        guard case .failed = state else {
            forwardCapturedAudio()
            observeLevels()
            return
        }
        await audioEngine.stop()
    }

    func end() async {
        eventTask?.cancel()
        audioForwardingTask?.cancel()
        levelTask?.cancel()
        await session.close()
        await audioEngine.stop()
        await flushPartialAssistantTranscript()
        state = .ended
    }

    func toggleMute() {
        isMuted.toggle()
        let muted = isMuted
        Task { await audioEngine.setMuted(muted) }
    }

    // MARK: - Connection

    private func connectSession(apiKey: String) async {
        do {
            let events = try await session.connect(
                apiKey: apiKey,
                model: Self.model,
                voice: voice,
                instructions: buildInstructions(),
                tools: toolContext.tools
            )
            state = .listening
            observeEvents(events)
        } catch {
            state = .failed(ChatServiceError.userFacingMessage(for: error))
        }
    }

    private func observeEvents(_ events: AsyncThrowingStream<RealtimeVoiceEvent, Error>) {
        eventTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in events {
                    guard !Task.isCancelled else { return }
                    await self.handle(event)
                }
                await self.handleStreamEnded(error: nil)
            } catch {
                await self.handleStreamEnded(error: error)
            }
        }
    }

    private func handleStreamEnded(error: Error?) async {
        guard state != .ended else { return }
        guard let error else {
            state = .ended
            return
        }
        guard !hasAttemptedReconnect,
              let provider = providerStore.provider(withID: "openai"),
              let apiKey = providerStore.apiKey(for: provider) else {
            state = .failed(ChatServiceError.userFacingMessage(for: error))
            return
        }
        hasAttemptedReconnect = true
        state = .reconnecting
        await NetworkMonitor.shared.waitForConnection()
        await connectSession(apiKey: apiKey)
    }

    private func forwardCapturedAudio() {
        audioForwardingTask = Task { [weak self] in
            guard let self else { return }
            for await chunk in self.audioEngine.capturedAudio {
                guard !Task.isCancelled else { return }
                try? await self.session.appendAudio(chunk)
            }
        }
    }

    private func observeLevels() {
        levelTask = Task { [weak self] in
            guard let self else { return }
            for await levels in self.audioEngine.levels {
                guard !Task.isCancelled else { return }
                if levels.input > 0 { self.inputLevel = levels.input }
                if levels.output > 0 { self.outputLevel = levels.output }
            }
        }
    }

    // MARK: - Event handling

    private func handle(_ event: RealtimeVoiceEvent) async {
        switch event {
        case .inputSpeechStarted:
            state = .userSpeaking
            partialAssistantTranscript = ""
            await audioEngine.stopPlayback()
        case .inputSpeechStopped:
            state = .listening
        case .inputTranscriptCompleted(let transcript):
            await commitMessage(role: .user, content: transcript)
        case .outputTranscriptDelta(let delta):
            state = .assistantSpeaking
            partialAssistantTranscript += delta
        case .outputTranscriptDone(let transcript):
            if !transcript.isEmpty { partialAssistantTranscript = transcript }
        case .outputAudioDelta(let audio):
            await audioEngine.enqueuePlayback(audio)
        case .outputAudioDone:
            break
        case .functionCallStarted(let callID, let name):
            pendingFunctionCalls[callID] = name
            state = .runningTool(Self.displayName(forTool: name))
        case .functionCallArgumentsDone(let callID, let arguments):
            await runTool(callID: callID, arguments: arguments)
        case .responseDone:
            await flushPartialAssistantTranscript()
            if state != .ended { state = .listening }
        case .error(let message):
            state = .failed(message)
        case .unknown:
            break
        }
    }

    private func runTool(callID: String, arguments: String) async {
        guard let name = pendingFunctionCalls.removeValue(forKey: callID) else { return }
        let call = ChatToolCall(id: callID, name: name, argumentsJSON: arguments)
        let output: String
        do {
            output = try await toolContext.execute(call)
        } catch {
            output = "Tool failed: \(error.localizedDescription)"
        }
        guard state != .ended else { return }
        state = .assistantSpeaking
        try? await session.sendFunctionCallOutput(callID: callID, output: output)
    }

    private static func displayName(forTool name: String) -> String {
        switch name {
        case WebSearchService.toolName: return "Searching the web…"
        case SkillToolService.invokeToolName: return "Loading a skill…"
        case SkillToolService.createToolName: return "Drafting a skill…"
        default: return "Using a tool…"
        }
    }

    // MARK: - Transcript -> ChatMessage

    private func commitMessage(role: MessageRole, content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let message = ChatMessage(
            role: role,
            content: trimmed,
            providerID: role == .assistant ? "openai" : nil,
            modelID: role == .assistant ? Self.model : nil,
            origin: .voice
        )
        message.conversation = conversation
        conversation.messages.append(message)
        modelContext.insert(message)
        conversation.updatedAt = .now
        try? modelContext.save()

        if role == .assistant {
            let proposals = await skillCollector.drainProposals()
            if !proposals.isEmpty {
                BackgroundGenerationService.shared.captureSkillProposals(
                    proposals,
                    messageID: message.id,
                    skillsStore: skillsStore,
                    modelContext: modelContext,
                    conversation: conversation
                )
            }
        }
    }

    private func flushPartialAssistantTranscript() async {
        guard !partialAssistantTranscript.isEmpty else { return }
        await commitMessage(role: .assistant, content: partialAssistantTranscript)
        partialAssistantTranscript = ""
    }

    // MARK: - Instructions & tools

    private func buildInstructions() -> String {
        let voiceGuidance = """
        You are having a live spoken conversation with the user through OpenChat's voice mode. \
        Keep replies concise and conversational — this is speech, not a written document.
        """

        var middleSections: [String] = [voiceGuidance]

        if MemoryStore.shouldUseMemory(isTemporary: conversation.isTemporary, useInChats: memoryStore.useInChats) {
            let items = (try? memoryStore.fetchItems(modelContext: modelContext)) ?? []
            if let memorySection = MemoryStore.contextSection(for: memoryStore.injectionItems(from: items)) {
                middleSections.append(memorySection)
            }
        }

        let globalRulesText: String
        if rulesStore.useGlobalRules {
            let items = (try? rulesStore.fetchItems(modelContext: modelContext)) ?? []
            globalRulesText = RulesStore.injectionText(from: items)
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
            chatRulesText = conversation.systemPrompt
        }

        return ChatSystemPromptBuilder.assemble(
            globalRules: globalRulesText,
            chatRules: chatRulesText,
            middleSections: middleSections,
            webSearchToolPrompt: nil
        ) ?? voiceGuidance
    }

    private func buildToolContext() -> (tools: [ChatToolDefinition], execute: @Sendable (ChatToolCall) async throws -> String) {
        var tools: [ChatToolDefinition] = []

        let searchAPIKey = webSearchStore.activeAPIKey()
        let searchClient = webSearchStore.makeActiveClient()
        let searchProviderName = webSearchStore.activeProviderDisplayName
        if webSearchStore.isActive, searchAPIKey != nil, searchClient != nil {
            tools.append(WebSearchService.toolDefinition(providerName: searchProviderName))
        }

        let skillToolsEnabled = skillsStore.isEnabled
        let skillMatches: [SkillMatchable] = skillToolsEnabled ? fetchSkillMatches() : []
        if skillToolsEnabled {
            tools.append(SkillToolService.invokeToolDefinition())
            tools.append(SkillToolService.createToolDefinition())
        }

        let collector = skillCollector
        let execute: @Sendable (ChatToolCall) async throws -> String = { call in
            switch call.name {
            case SkillToolService.invokeToolName:
                guard let slashName = SkillToolService.slashName(fromInvokeArguments: call.argumentsJSON),
                      let matched = skillMatches.first(
                          where: { $0.slashName == SkillResolver.normalizeSlashName(slashName) }
                      ) else {
                    return "No skill found with that slash name."
                }
                await collector.recordInvoke(matched)
                return SkillResolver.systemBlock(for: matched)
            case SkillToolService.createToolName:
                guard let proposal = SkillToolService.proposal(fromCreateArguments: call.argumentsJSON) else {
                    return "Could not parse the skill draft — name, slash_name, and instructions must be non-empty."
                }
                await collector.recordProposal(proposal)
                return "Draft captured. The user will review \"\(proposal.name)\" before it's saved."
            case WebSearchService.toolName:
                guard let searchAPIKey, let searchClient else {
                    return "Search is not configured."
                }
                return try await WebSearchService.executeToolCall(call, apiKey: searchAPIKey, client: searchClient)
            default:
                return "Unknown tool: \(call.name)"
            }
        }

        return (tools, execute)
    }

    private func fetchSkillMatches() -> [SkillMatchable] {
        guard skillsStore.isEnabled else { return [] }
        let skills = (try? modelContext.fetch(FetchDescriptor<Skill>())) ?? []
        return SkillResolver.withBuiltIns(skills.map(SkillMatchable.init(skill:)))
    }
}

import Foundation
import SwiftData

extension BackgroundGenerationService {
    func buildTurns(
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

    func runStream(
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

        // Runs on every exit path — including a mid-stream throw — so a
        // network drop can never silently lose the last (up to
        // flushInterval-old) chunk of text that already arrived.
        defer {
            if !contentBuffer.isEmpty {
                assistantMessage.content += contentBuffer
                contentBuffer = ""
            }
        }

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
                assistantMessage.imageAttachments = GeneratedImageDeduper.merging(
                    images,
                    into: assistantMessage.imageAttachments
                )
            }
        }
    }
}

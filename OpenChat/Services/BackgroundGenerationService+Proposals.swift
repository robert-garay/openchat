import Foundation
import SwiftData

extension BackgroundGenerationService {
    func fetchSkillMatches(using skillsStore: SkillsStore, modelContext: ModelContext) -> [SkillMatchable] {
        guard skillsStore.isEnabled else { return [] }
        let skills = (try? modelContext.fetch(FetchDescriptor<Skill>())) ?? []
        return SkillResolver.withBuiltIns(skills.map(SkillMatchable.init(skill:)))
    }

    func insertSkillSystemMessage(
        for skill: SkillMatchable,
        conversation: Conversation,
        modelContext: ModelContext
    ) {
        let message = ChatMessage(role: .system, content: SkillResolver.systemBlock(for: skill))
        message.conversation = conversation
        conversation.messages.append(message)
        modelContext.insert(message)
    }

    func captureCalendarProposals(
        from message: ChatMessage,
        dataSourceStore: AgentDataSourceStore
    ) {
        guard dataSourceStore.canEditCalendar else { return }
        let proposals = CalendarActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        NotificationCenter.default.post(
            name: .bgGenCapturedCalendarProposals,
            object: nil,
            userInfo: ["messageID": message.id, "proposals": proposals]
        )
    }

    func captureRemindersProposals(
        from message: ChatMessage,
        dataSourceStore: AgentDataSourceStore
    ) {
        guard dataSourceStore.canEditReminders else { return }
        let proposals = RemindersActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        NotificationCenter.default.post(
            name: .bgGenCapturedRemindersProposals,
            object: nil,
            userInfo: ["messageID": message.id, "proposals": proposals]
        )
    }

    func captureContactsProposals(
        from message: ChatMessage,
        dataSourceStore: AgentDataSourceStore
    ) {
        guard dataSourceStore.canEditContacts else { return }
        let proposals = ContactsActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        NotificationCenter.default.post(
            name: .bgGenCapturedContactsProposals,
            object: nil,
            userInfo: ["messageID": message.id, "proposals": proposals]
        )
    }

    func captureMemoryProposals(
        from message: ChatMessage,
        memoryStore: MemoryStore,
        modelContext: ModelContext,
        conversation: Conversation
    ) {
        guard MemoryStore.shouldUseMemory(
            isTemporary: conversation.isTemporary,
            useInChats: memoryStore.useInChats
        ) else { return }
        let proposals = MemoryActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        if memoryStore.requireConfirmation {
            NotificationCenter.default.post(
                name: .bgGenCapturedMemoryProposals,
                object: nil,
                userInfo: ["messageID": message.id, "proposals": proposals]
            )
        } else {
            saveMemoryProposals(proposals, source: .auto, messageID: message.id, memoryStore: memoryStore, modelContext: modelContext)
        }
    }

    func saveMemoryProposals(
        _ proposals: [MemoryProposal],
        source: MemorySource,
        messageID: UUID,
        memoryStore: MemoryStore,
        modelContext: ModelContext
    ) {
        var saved = 0
        for proposal in proposals {
            do {
                _ = try memoryStore.save(content: proposal.content, source: source, modelContext: modelContext)
                saved += 1
            } catch {
                NotificationCenter.default.post(
                    name: .bgGenMemorySaveFailed,
                    object: nil,
                    userInfo: ["messageID": messageID, "error": error.localizedDescription]
                )
                return
            }
        }
        if saved > 0 {
            try? modelContext.save()
        }
    }

    func captureRuleProposals(
        from message: ChatMessage,
        rulesStore: RulesStore,
        modelContext: ModelContext,
        conversation: Conversation
    ) {
        guard RulesStore.shouldAllowRuleProposals(
            isTemporary: conversation.isTemporary,
            allowProposalsFromChat: rulesStore.allowProposalsFromChat
        ) else { return }
        let proposals = RuleActionParser.parse(message.content)
        guard !proposals.isEmpty else { return }
        if rulesStore.requireConfirmation {
            NotificationCenter.default.post(
                name: .bgGenCapturedRuleProposals,
                object: nil,
                userInfo: ["messageID": message.id, "proposals": proposals]
            )
        } else {
            saveRuleProposals(proposals, messageID: message.id, rulesStore: rulesStore, modelContext: modelContext, conversation: conversation)
        }
    }

    func saveRuleProposals(
        _ proposals: [RuleProposal],
        messageID: UUID,
        rulesStore: RulesStore,
        modelContext: ModelContext,
        conversation: Conversation
    ) {
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
                NotificationCenter.default.post(
                    name: .bgGenRuleSaveFailed,
                    object: nil,
                    userInfo: ["messageID": messageID, "error": error.localizedDescription]
                )
                return
            }
        }
        if saved > 0 {
            try? modelContext.save()
        }
    }

    func captureSkillProposals(
        _ proposals: [SkillProposal],
        messageID: UUID,
        skillsStore: SkillsStore,
        modelContext: ModelContext,
        conversation: Conversation
    ) {
        guard !proposals.isEmpty else { return }
        if skillsStore.requireConfirmation {
            NotificationCenter.default.post(
                name: .bgGenCapturedSkillProposals,
                object: nil,
                userInfo: ["messageID": messageID, "proposals": proposals]
            )
        } else {
            saveSkillProposals(proposals, messageID: messageID, skillsStore: skillsStore, modelContext: modelContext, conversation: conversation)
        }
    }

    func saveSkillProposals(
        _ proposals: [SkillProposal],
        messageID: UUID,
        skillsStore: SkillsStore,
        modelContext: ModelContext,
        conversation: Conversation
    ) {
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
                NotificationCenter.default.post(
                    name: .bgGenSkillSaveFailed,
                    object: nil,
                    userInfo: ["messageID": messageID, "error": error.localizedDescription]
                )
                return
            }
        }
        if saved > 0 {
            try? modelContext.save()
        }
    }
}

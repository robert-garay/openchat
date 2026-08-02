import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class ChatViewModel {
    private(set) var isStreaming = false
    var composerText = ""

    private let conversation: Conversation
    private let modelContext: ModelContext
    private let providerStore: ProviderStore
    private var streamingTask: Task<Void, Never>?

    init(conversation: Conversation, modelContext: ModelContext, providerStore: ProviderStore) {
        self.conversation = conversation
        self.modelContext = modelContext
        self.providerStore = providerStore
    }

    var currentProvider: ConfiguredProvider? {
        providerStore.provider(withID: conversation.providerID)
    }

    var currentModel: AIModel? {
        providerStore.model(providerID: conversation.providerID, modelID: conversation.modelID)
    }

    func selectModel(providerID: String, modelID: String) {
        conversation.providerID = providerID
        conversation.modelID = modelID
        conversation.updatedAt = .now
    }

    func send() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        composerText = ""

        let userMessage = ChatMessage(role: .user, content: text)
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)
        modelContext.insert(userMessage)

        if conversation.title == "New Chat" {
            conversation.title = String(text.prefix(40))
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

        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        assistantMessage.conversation = conversation
        conversation.messages.append(assistantMessage)
        modelContext.insert(assistantMessage)

        var turns: [ChatTurn] = []
        if !conversation.systemPrompt.isEmpty {
            turns.append(ChatTurn(role: .system, content: conversation.systemPrompt))
        }
        turns.append(contentsOf: conversation.sortedMessages
            .filter { $0.id != assistantMessage.id && !$0.content.isEmpty }
            .map { ChatTurn(role: $0.role, content: $0.content) })

        isStreaming = true
        let client = ChatService.client(for: provider.apiFormat)
        let baseURL = provider.baseURL
        let modelID = model.id

        streamingTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await delta in client.streamReply(turns: turns, model: modelID, baseURL: baseURL, apiKey: apiKey) {
                    assistantMessage.content += delta
                }
                assistantMessage.isStreaming = false
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
}

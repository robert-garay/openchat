import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var selectedConversationID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var showingSettings = false

    private var persistedConversations: [Conversation] {
        conversations.filter { !$0.isTemporary }
    }

    private var selectedConversation: Conversation? {
        conversations.first(where: { $0.id == selectedConversationID })
    }

    var body: some View {
        Group {
            if providerStore.enabledProviders.isEmpty {
                WelcomeView()
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    ConversationListView(
                        conversations: persistedConversations,
                        selectedConversationID: $selectedConversationID,
                        onNewChat: { startNewChat(temporary: false) },
                        onShowSettings: { showingSettings = true }
                    )
                } detail: {
                    if let conversation = selectedConversation {
                        ChatView(
                            conversation: conversation,
                            onToggleTemporary: { toggleTemporary(for: conversation) }
                        )
                        .id(conversation.id)
                    } else {
                        EmptyChatDetailView(onNewChat: { startNewChat(temporary: false) })
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            discardOrphanedTemporaryChats()
        }
        .onChange(of: selectedConversationID) { previousID, _ in
            discardTemporaryChat(id: previousID)
        }
        .onChange(of: providerStore.enabledProviders.isEmpty) { _, isEmpty in
            if isEmpty { selectedConversationID = nil }
        }
    }

    private func startNewChat(temporary: Bool, preferring source: Conversation? = nil) {
        let providerID: String
        let modelID: String

        if let source,
           providerStore.provider(withID: source.providerID) != nil,
           providerStore.model(providerID: source.providerID, modelID: source.modelID) != nil {
            providerID = source.providerID
            modelID = source.modelID
        } else if let provider = providerStore.enabledProviders.first,
                  let model = provider.models.first {
            providerID = provider.id
            modelID = model.id
        } else {
            return
        }

        let conversation = Conversation(
            title: temporary ? "Temporary Chat" : "New Chat",
            providerID: providerID,
            modelID: modelID,
            isTemporary: temporary
        )
        modelContext.insert(conversation)
        selectedConversationID = conversation.id
        columnVisibility = .detailOnly
    }

    private func toggleTemporary(for conversation: Conversation) {
        if conversation.isTemporary {
            startNewChat(temporary: false, preferring: conversation)
            return
        }

        let discardEmptySource = conversation.messages.isEmpty
        startNewChat(temporary: true, preferring: conversation)
        if discardEmptySource {
            modelContext.delete(conversation)
        }
    }

    private func discardTemporaryChat(id: UUID?) {
        guard let id,
              let conversation = conversations.first(where: { $0.id == id }),
              conversation.isTemporary else { return }
        modelContext.delete(conversation)
    }

    private func discardOrphanedTemporaryChats() {
        for conversation in conversations where conversation.isTemporary {
            if conversation.id == selectedConversationID { continue }
            modelContext.delete(conversation)
        }
    }
}

private struct EmptyChatDetailView: View {
    let onNewChat: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Chat Selected", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Pick a conversation, or start a new one.")
        } actions: {
            Button("New Chat", action: onNewChat)
                .buttonStyle(.borderedProminent)
        }
    }
}

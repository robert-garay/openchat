import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var selectedConversationID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var showingSettings = false

    /// Sidebar history: never temporary, never empty (no user messages).
    /// Keep the currently selected empty chat visible so List selection stays stable.
    /// Pinned chats stay above unpinned, each group by recency.
    private var listConversations: [Conversation] {
        conversations
            .filter { conversation in
                if conversation.isTemporary { return false }
                return conversation.hasUserMessages || conversation.id == selectedConversationID
            }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned && !rhs.isPinned
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private var selectedConversation: Conversation? {
        conversations.first(where: { $0.id == selectedConversationID })
    }

    /// Ignores List clearing selection when the active chat isn’t in sidebar data
    /// (temporary chats, or empty chats mid-transition).
    private var listSelection: Binding<UUID?> {
        Binding(
            get: { selectedConversationID },
            set: { newValue in
                if newValue == nil,
                   let current = selectedConversationID,
                   conversations.contains(where: { $0.id == current }),
                   !listConversations.contains(where: { $0.id == current }) {
                    return
                }
                selectedConversationID = newValue
            }
        )
    }

    var body: some View {
        Group {
            if providerStore.enabledProviders.isEmpty {
                WelcomeView()
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    ConversationListView(
                        conversations: listConversations,
                        selectedConversationID: listSelection,
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
            discardOrphanedEphemeralChats()
        }
        .onChange(of: selectedConversationID) { previousID, _ in
            discardEphemeralChat(id: previousID)
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
        // Flip in place — recreating a chat races List selection / ephemeral
        // discard and often eats the first tap.
        conversation.toggleTemporaryMode()
    }

    private func discardEphemeralChat(id: UUID?) {
        guard let id,
              let conversation = conversations.first(where: { $0.id == id }) else { return }
        guard conversation.isTemporary || !conversation.hasUserMessages else { return }
        modelContext.delete(conversation)
    }

    private func discardOrphanedEphemeralChats() {
        for conversation in conversations {
            if conversation.id == selectedConversationID { continue }
            if conversation.isTemporary || !conversation.hasUserMessages {
                modelContext.delete(conversation)
            }
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

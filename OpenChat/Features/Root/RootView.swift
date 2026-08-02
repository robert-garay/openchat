import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var selectedConversationID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var showingSettings = false

    var body: some View {
        Group {
            if providerStore.enabledProviders.isEmpty {
                WelcomeView()
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    ConversationListView(
                        conversations: conversations,
                        selectedConversationID: $selectedConversationID,
                        onNewChat: startNewChat,
                        onShowSettings: { showingSettings = true }
                    )
                } detail: {
                    if let conversation = conversations.first(where: { $0.id == selectedConversationID }) {
                        ChatView(conversation: conversation)
                            .id(conversation.id)
                    } else {
                        EmptyChatDetailView(onNewChat: startNewChat)
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onChange(of: providerStore.enabledProviders.isEmpty) { _, isEmpty in
            if isEmpty { selectedConversationID = nil }
        }
    }

    private func startNewChat() {
        guard let provider = providerStore.enabledProviders.first,
              let model = provider.models.first else { return }
        let conversation = Conversation(providerID: provider.id, modelID: model.id)
        modelContext.insert(conversation)
        selectedConversationID = conversation.id
        columnVisibility = .detailOnly
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

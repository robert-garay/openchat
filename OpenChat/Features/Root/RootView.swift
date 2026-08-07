import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var selectedConversationID: UUID?
    @State private var showingSettings = false
    @State private var showingHistoryDrawer = false

    /// Sidebar history: never temporary, never empty (no user messages).
    /// Keep the currently selected empty chat visible so the selection stays stable.
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

    var body: some View {
        Group {
            if providerStore.enabledProviders.isEmpty {
                WelcomeView()
            } else {
                mainContent
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            guard !providerStore.enabledProviders.isEmpty else { return }
            discardOrphanedEphemeralChats()
            providerStore.seedModelUsageFromConversationsIfNeeded(
                conversations.map { (providerID: $0.providerID, modelID: $0.modelID) }
            )
            if let recent = conversations.first(where: { conversation in
                providerStore.enabledProviders.contains(where: { $0.id == conversation.providerID })
                    && providerStore.model(providerID: conversation.providerID, modelID: conversation.modelID) != nil
            }) {
                providerStore.seedLastSelectedModelIfNeeded(
                    providerID: recent.providerID,
                    modelID: recent.modelID
                )
            }
            if selectedConversationID == nil {
                startNewChat(temporary: false)
            }
        }
        .onChange(of: selectedConversationID) { previousID, _ in
            discardEphemeralChat(id: previousID)
        }
        .onChange(of: providerStore.enabledProviders.isEmpty) { _, isEmpty in
            if isEmpty {
                selectedConversationID = nil
                showingHistoryDrawer = false
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        NavigationStack {
            ZStack {
                if let conversation = selectedConversation {
                    ChatView(
                        conversation: conversation,
                        onToggleTemporary: { toggleTemporary(for: conversation) },
                        onShowHistory: { showingHistoryDrawer.toggle() }
                    )
                    .id(conversation.id)
                } else {
                    // Stable placeholder while the first chat is created.
                    ProgressView()
                        .controlSize(.large)
                }

                if showingHistoryDrawer {
                    drawerOverlay
                }
            }
        }
    }

    private var drawerOverlay: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingHistoryDrawer = false
                    }
                    .transition(.opacity)

                ChatHistoryDrawerView(
                    conversations: listConversations,
                    selectedConversationID: $selectedConversationID,
                    onNewChat: { startNewChat(temporary: false) },
                    onClose: { showingHistoryDrawer = false },
                    onShowSettings: { showingSettings = true }
                )
                .frame(width: min(geometry.size.width * 0.85, 360))
                .background(.background)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 4, y: 0)
                .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingHistoryDrawer)
    }

    private func startNewChat(temporary: Bool, preferring source: Conversation? = nil) {
        let providerID: String
        let modelID: String

        if let source,
           providerStore.provider(withID: source.providerID) != nil,
           providerStore.model(providerID: source.providerID, modelID: source.modelID) != nil {
            providerID = source.providerID
            modelID = source.modelID
        } else if let choice = providerStore.defaultModelForNewChat() {
            providerID = choice.providerID
            modelID = choice.modelID
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
    }

    private func toggleTemporary(for conversation: Conversation) {
        // Flip in place — recreating a chat races selection / ephemeral
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

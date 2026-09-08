import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var selectedConversationID: UUID?
    @State private var showingSettings = false
    @State private var showingHistoryDrawer = false

    /// Sidebar history: never temporary, never unstarted, and never a placeholder title.
    /// Pinned chats stay above unpinned, each group by recency.
    private var listConversations: [Conversation] {
        conversations
            .filter { conversation in
                if conversation.isTemporary { return false }
                if conversation.needsAutoTitle { return false }
                return true
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
            bootstrapMainSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notificationOpenedConversation)) { notification in
            guard let id = notification.userInfo?["conversationID"] as? UUID else { return }
            guard conversations.contains(where: { $0.id == id }) else { return }
            selectedConversationID = id
            showingHistoryDrawer = false
        }
        .onChange(of: selectedConversationID) { previousID, newID in
            discardEphemeralChat(id: previousID)
            BackgroundGenerationService.shared.setVisibleConversationID(newID)
        }
        .onChange(of: scenePhase) { _, phase in
            BackgroundGenerationService.shared.setVisibleConversationID(
                phase == .active ? selectedConversationID : nil
            )
        }
        .onChange(of: providerStore.enabledProviders.isEmpty) { _, isEmpty in
            if isEmpty {
                selectedConversationID = nil
                showingHistoryDrawer = false
            } else {
                bootstrapMainSession()
            }
        }
        .onChange(of: providerStore.loadedModelCount) { _, _ in
            guard selectedConversationID == nil, !providerStore.enabledProviders.isEmpty else { return }
            startNewChat(temporary: false)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    if let conversation = selectedConversation {
                        ChatView(
                            conversation: conversation,
                            onToggleTemporary: { toggleTemporary(for: conversation) },
                            onShowHistory: { toggleHistoryDrawer() },
                            isHistoryDrawerOpen: showingHistoryDrawer
                        )
                        .id(conversation.id)
                        .offset(x: showingHistoryDrawer ? geometry.size.width : 0)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { value in
                                    let horizontal = value.translation.width
                                    let vertical = value.translation.height
                                    if !showingHistoryDrawer, horizontal > 80, abs(vertical) < abs(horizontal) {
                                        Haptics.light()
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            showingHistoryDrawer = true
                                        }
                                    }
                                }
                        )
                    } else {
                        // Placeholder while the first chat is created, or after a catalog miss.
                        firstChatPlaceholder
                            .offset(x: showingHistoryDrawer ? geometry.size.width : 0)
                    }

                    drawerOverlay
                        .offset(x: showingHistoryDrawer ? 0 : -geometry.size.width)
                        .allowsHitTesting(showingHistoryDrawer)
                        .accessibilityHidden(!showingHistoryDrawer)
                }
            }
        }
    }

    private var drawerOverlay: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ChatHistoryDrawerView(
                conversations: listConversations,
                selectedConversationID: $selectedConversationID,
                onNewChat: { startNewChat(temporary: false) },
                onClose: { withAnimation(.easeInOut(duration: 0.25)) { showingHistoryDrawer = false } },
                onShowSettings: { showingSettings = true }
            )
        }
    }

    private var firstChatPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            if providerStore.isLoadingModels {
                Text("Loading models…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let message = firstChatLoadError {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Try Again") {
                    providerStore.refreshModelsIfNeeded(force: true)
                    startNewChat(temporary: false)
                }
            }
        }
    }

    private var firstChatLoadError: String? {
        if let message = providerStore.openRouterModelsError {
            return message
        }
        return providerStore.liveModelErrors.values.first
    }

    /// Runs after launch and after the first provider is saved from onboarding.
    /// `onAppear` alone is not enough: it already fired on `WelcomeView`.
    private func bootstrapMainSession() {
        guard !providerStore.enabledProviders.isEmpty else { return }
        providerStore.refreshModelsIfNeeded()
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

    private func toggleHistoryDrawer() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showingHistoryDrawer.toggle()
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

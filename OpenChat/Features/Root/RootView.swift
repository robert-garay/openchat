import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var selectedConversationID: UUID?
    @State private var showingSettings = false
    @State private var drawerProgress: CGFloat = 0
    @State private var drawerWidth: CGFloat = 0

    private var isDrawerOpen: Bool { drawerProgress > 0.5 }

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
                drawerProgress = 0
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        NavigationStack {
            GeometryReader { geometry in
                let width = min(geometry.size.width * 0.85, 360)
                ZStack {
                    chatView
                    drawerOverlay(width: width)
                }
                .onAppear { drawerWidth = width }
                .onChange(of: width) { _, new in drawerWidth = new }
            }
        }
    }

    @ViewBuilder
    private var chatView: some View {
        if let conversation = selectedConversation {
            ChatView(
                conversation: conversation,
                onToggleTemporary: { toggleTemporary(for: conversation) },
                onShowHistory: { toggleDrawer() },
                isHistoryDrawerOpen: drawerProgress > 0
            )
            .id(conversation.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .simultaneousGesture(openDrawerGesture)
        } else {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        }
    }

    private var openDrawerGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard drawerProgress < 1, horizontal > 0, horizontal > abs(vertical) else { return }
                let progress = min(1, horizontal / drawerWidth)
                drawerProgress = progress
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard drawerProgress < 1, horizontal > 0, horizontal > abs(vertical) else { return }
                let velocity = value.predictedEndLocation.x - value.location.x
                let shouldOpen = horizontal > drawerWidth * 0.25 || velocity > 120
                withAnimation(.easeInOut(duration: 0.25)) {
                    drawerProgress = shouldOpen ? 1 : 0
                }
            }
    }

    private func toggleDrawer() {
        withAnimation(.easeInOut(duration: 0.25)) {
            drawerProgress = isDrawerOpen ? 0 : 1
        }
    }

    private func drawerOverlay(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.4 * drawerProgress)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        drawerProgress = 0
                    }
                }
                .allowsHitTesting(drawerProgress > 0.01)

            ChatHistoryDrawerView(
                conversations: listConversations,
                selectedConversationID: $selectedConversationID,
                onNewChat: { startNewChat(temporary: false) },
                onClose: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        drawerProgress = 0
                    }
                },
                onShowSettings: { showingSettings = true }
            )
            .frame(width: width, alignment: .leading)
            .background(.background)
            .offset(x: -width * (1 - drawerProgress))
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        guard drawerProgress > 0, horizontal < 0, abs(horizontal) > abs(vertical) else { return }
                        let progress = max(0, 1 + horizontal / width)
                        drawerProgress = progress
                    }
                    .onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        guard drawerProgress > 0, horizontal < 0, abs(horizontal) > abs(vertical) else { return }
                        let velocity = value.predictedEndLocation.x - value.location.x
                        let shouldClose = abs(horizontal) > width * 0.25 || velocity < -120
                        withAnimation(.easeInOut(duration: 0.25)) {
                            drawerProgress = shouldClose ? 0 : 1
                        }
                    }
            )
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

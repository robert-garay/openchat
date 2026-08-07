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
    @State private var isDragging = false
    @State private var dragStartProgress: CGFloat = 0

    private var isDrawerOpen: Bool { drawerProgress > 0.5 }
    private var effectiveDrawerWidth: CGFloat { drawerWidth > 0 ? drawerWidth : 300 }

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
        GeometryReader { geometry in
            let width = min(geometry.size.width * 0.85, 360)
            ZStack {
                // History drawer sits behind the chat panel.
                ChatHistoryDrawerView(
                    conversations: listConversations,
                    selectedConversationID: $selectedConversationID,
                    onNewChat: { startNewChat(temporary: false) },
                    onClose: { closeDrawer() },
                    onShowSettings: { showingSettings = true }
                )
                .frame(width: width)
                .frame(maxHeight: .infinity, alignment: .leading)
                .background(.background)
                .simultaneousGesture(drawerGesture)

                // Chat panel slides to the right, rounds its leading edge,
                // and darkens as the drawer is revealed.
                chatContent
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .offset(x: drawerProgress * width)
                    .clipShape(LeadingRoundedRectangle(radius: drawerProgress * 24))
                    .shadow(color: .black.opacity(0.25), radius: 20, x: -8, y: 0)
                    .simultaneousGesture(drawerGesture)
            }
            .onAppear { drawerWidth = width }
            .onChange(of: width) { _, new in drawerWidth = new }
        }
    }

    @ViewBuilder
    private var chatContent: some View {
        if let conversation = selectedConversation {
            ChatView(
                conversation: conversation,
                onToggleTemporary: { toggleTemporary(for: conversation) },
                onShowHistory: { toggleDrawer() },
                drawerProgress: drawerProgress
            )
            .id(conversation.id)
        } else {
            ProgressView()
                .controlSize(.large)
        }
    }

    private var drawerGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                if !isDragging {
                    isDragging = true
                    dragStartProgress = drawerProgress
                }
                let progress = dragStartProgress + horizontal / effectiveDrawerWidth
                drawerProgress = max(0, min(1, progress))
            }
            .onEnded { value in
                isDragging = false
                let wasOpen = isDrawerOpen
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let velocity = value.predictedEndLocation.x - value.location.x
                if abs(horizontal) > abs(vertical), abs(velocity) > 120 {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        drawerProgress = velocity > 0 ? 1 : 0
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        drawerProgress = drawerProgress > 0.5 ? 1 : 0
                    }
                }
                if isDrawerOpen != wasOpen {
                    Haptics.light()
                }
            }
    }

    private func toggleDrawer() {
        withAnimation(.easeInOut(duration: 0.25)) {
            drawerProgress = isDrawerOpen ? 0 : 1
        }
    }

    private func closeDrawer() {
        withAnimation(.easeInOut(duration: 0.25)) {
            drawerProgress = 0
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

private struct LeadingRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, rect.width / 2, rect.height / 2)
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(-180),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}


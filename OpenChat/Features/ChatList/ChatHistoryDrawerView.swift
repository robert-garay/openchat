import SwiftUI
import SwiftData

/// Grok-style full-screen conversation history drawer.
struct ChatHistoryDrawerView: View {
    let conversations: [Conversation]
    @Binding var selectedConversationID: UUID?
    let onNewChat: () -> Void
    let onClose: () -> Void
    let onShowSettings: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ProviderStore.self) private var providerStore
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var conversationPendingRename: Conversation?
    @State private var renameText = ""
    @State private var activeMenu: Conversation?

    private var filtered: [Conversation] {
        guard !searchText.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.lastMessagePreview.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var pinned: [Conversation] { filtered.filter(\.isPinned) }
    private var recents: [Conversation] { filtered.filter { !$0.isPinned } }

    private var isRenameAlertPresented: Binding<Bool> {
        Binding(
            get: { conversationPendingRename != nil },
            set: { if !$0 { conversationPendingRename = nil } }
        )
    }

    var body: some View {
        ZStack {
            drawerContent
                .background(.background)

            if let activeMenu {
                contextMenuOverlay(for: activeMenu)
            }
        }
        .alert("Rename Chat", isPresented: isRenameAlertPresented) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {
                conversationPendingRename = nil
            }
            Button("Rename") {
                applyRename()
            }
        } message: {
            Text("Enter a new name for this chat.")
        }
    }

    private var drawerContent: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)

            Divider()

            if conversations.isEmpty {
                Spacer(minLength: 24)
                ContentUnavailableView {
                    Label("No Chats Yet", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Start a new conversation with any connected model.")
                } actions: {
                    Button("New Chat", action: newChatAndClose)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)
                Spacer(minLength: 24)
            } else {
                List {
                    if !pinned.isEmpty {
                        Section {
                            ForEach(pinned) { conversation in
                                conversationRow(conversation)
                            }
                        } header: {
                            sectionHeader("Pinned")
                        }
                    }
                    if !recents.isEmpty {
                        Section {
                            ForEach(recents) { conversation in
                                conversationRow(conversation)
                            }
                        } header: {
                            sectionHeader("Conversations")
                        }
                    }
                }
                .listStyle(.plain)
                .listRowSpacing(0)
                .listSectionSpacing(0)
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }

            Divider()

            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.width < -80 {
                        Haptics.light()
                        onClose()
                    }
                }
        )
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("OpenChat")
                .font(.title2.weight(.bold))

            Spacer(minLength: 12)

            Button(action: onClose) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to chat")
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("Search chats", text: $searchText)
                    .font(.subheadline)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if isSearchFocused {
                Button(action: exitSearch) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exit search")
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .opacity
                ))
            } else {
                HStack(spacing: 12) {
                    Button(action: onShowSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(.secondarySystemBackground), in: Circle())
                    }
                    .accessibilityLabel("Settings")

                    Button(action: newChatAndClose) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor, in: Circle())
                    }
                    .accessibilityLabel("New chat")
                }
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .scale(scale: 0.8).combined(with: .opacity)
                ))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }

    private func exitSearch() {
        searchText = ""
        isSearchFocused = false
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    private func newChatAndClose() {
        onNewChat()
        onClose()
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        ConversationRow(
            conversation: conversation,
            isSelected: selectedConversationID == conversation.id
        )
        .contentShape(Rectangle())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .onTapGesture {
            selectedConversationID = conversation.id
            onClose()
        }
        .onLongPressGesture {
            Haptics.medium()
            activeMenu = conversation
        }
        .environment(providerStore)
    }

    private func contextMenuOverlay(for conversation: Conversation) -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        activeMenu = nil
                    }
                    .transition(.opacity)

                VStack(spacing: 0) {
                    contextMenuButton(
                        icon: conversation.isPinned ? "pin.slash" : "pin",
                        label: conversation.isPinned ? "Unpin" : "Pin",
                        action: {
                            togglePin(conversation)
                            activeMenu = nil
                        }
                    )
                    menuDivider
                    contextMenuButton(
                        icon: "pencil",
                        label: "Rename",
                        action: {
                            beginRename(conversation)
                            activeMenu = nil
                        }
                    )
                    menuDivider
                    contextMenuButton(
                        icon: "trash",
                        label: "Delete",
                        isDestructive: true,
                        action: {
                            delete(conversation)
                            activeMenu = nil
                        }
                    )
                }
                .background(.bar, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
                .frame(maxWidth: 260)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: activeMenu != nil)
    }

    private var menuDivider: some View {
        Divider()
            .background(.white.opacity(0.12))
            .padding(.horizontal, 16)
    }

    private func contextMenuButton(
        icon: String,
        label: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 22)
                Text(label)
                    .font(.body)
                Spacer()
            }
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func beginRename(_ conversation: Conversation) {
        Haptics.light()
        renameText = conversation.title
        conversationPendingRename = conversation
    }

    private func applyRename() {
        guard let conversation = conversationPendingRename else { return }
        conversation.rename(to: renameText)
        conversationPendingRename = nil
        Haptics.light()
    }

    private func togglePin(_ conversation: Conversation) {
        Haptics.light()
        withAnimation(Theme.springFast) {
            conversation.togglePinned()
        }
    }

    private func delete(_ conversation: Conversation) {
        Haptics.light()
        withAnimation(Theme.springFast) {
            let wasSelected = selectedConversationID == conversation.id
            if conversationPendingRename?.id == conversation.id {
                conversationPendingRename = nil
            }
            modelContext.delete(conversation)
            if wasSelected {
                onNewChat()
                onClose()
            }
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool

    @Environment(ProviderStore.self) private var providerStore

    private var provider: ConfiguredProvider? {
        providerStore.provider(withID: conversation.providerID)
    }

    private var providerTint: Color {
        provider.map { Color(hex: $0.tint) } ?? .accentColor
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ProviderLogoView(
                logoAssetName: provider?.logoAssetName,
                symbolName: provider?.symbolName ?? "sparkles",
                tint: providerTint,
                size: 28,
                cornerRadius: 7
            )

            Text(conversation.title)
                .font(.body)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
        )
        .accessibilityLabel(
            conversation.isPinned
                ? "Pinned, \(conversation.title)"
                : conversation.title
        )
    }
}

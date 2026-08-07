import SwiftUI
import SwiftData

/// ChatGPT-style slide-in drawer that exposes the conversation history.
/// It reuses the same pin/rename/delete actions the old sidebar had, but
/// presents them as a focused overlay on top of the current chat.
struct ChatHistoryDrawerView: View {
    let conversations: [Conversation]
    @Binding var selectedConversationID: UUID?
    let onNewChat: () -> Void
    let onClose: () -> Void
    let onShowSettings: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var conversationPendingRename: Conversation?
    @State private var renameText = ""

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
                        Section("Pinned") {
                            ForEach(pinned) { conversation in
                                conversationRow(conversation)
                            }
                        }
                    }
                    if !recents.isEmpty {
                        Section("Recents") {
                            ForEach(recents) { conversation in
                                conversationRow(conversation)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search chats")
            }

            Divider()

            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(.background)
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

    private var header: some View {
        HStack(spacing: 0) {
            Text("OpenChat")
                .font(.title2.weight(.bold))
            Spacer(minLength: 12)
            Button(action: onClose) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Close history")
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button(action: newChatAndClose) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                    Text("New Chat")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("New chat")

            Spacer(minLength: 12)

            Button(action: onShowSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Settings")
        }
    }

    private func newChatAndClose() {
        onNewChat()
        onClose()
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        Button {
            selectedConversationID = conversation.id
            onClose()
        } label: {
            ConversationRow(conversation: conversation)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selectedConversationID == conversation.id ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contextMenu {
            Button {
                togglePin(conversation)
            } label: {
                Label(
                    conversation.isPinned ? "Unpin" : "Pin",
                    systemImage: conversation.isPinned ? "pin.slash" : "pin"
                )
            }
            Button {
                beginRename(conversation)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                delete(conversation)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                togglePin(conversation)
            } label: {
                Label(
                    conversation.isPinned ? "Unpin" : "Pin",
                    systemImage: conversation.isPinned ? "pin.slash" : "pin"
                )
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                delete(conversation)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
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

    var body: some View {
        HStack(spacing: 12) {
            if conversation.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(conversation.title)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
        .accessibilityLabel(conversation.isPinned ? "Pinned, \(conversation.title)" : conversation.title)
    }
}

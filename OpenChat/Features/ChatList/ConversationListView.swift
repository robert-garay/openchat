import SwiftUI
import SwiftData

struct ConversationListView: View {
    let conversations: [Conversation]
    @Binding var selectedConversationID: UUID?
    let onNewChat: () -> Void
    let onShowSettings: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ProviderStore.self) private var providerStore
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

    private var isRenameAlertPresented: Binding<Bool> {
        Binding(
            get: { conversationPendingRename != nil },
            set: { if !$0 { conversationPendingRename = nil } }
        )
    }

    var body: some View {
        Group {
            if conversations.isEmpty {
                ContentUnavailableView {
                    Label("No Chats Yet", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Start a new conversation with any connected model.")
                } actions: {
                    Button("New Chat", action: onNewChat)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: $selectedConversationID) {
                    ForEach(filtered) { conversation in
                        ConversationRow(conversation: conversation, providerStore: providerStore)
                            .tag(conversation.id)
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
                }
                .searchable(text: $searchText, prompt: "Search chats")
                .listStyle(.plain)
            }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onShowSettings) {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                }
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
            if selectedConversationID == conversation.id {
                selectedConversationID = nil
            }
            if conversationPendingRename?.id == conversation.id {
                conversationPendingRename = nil
            }
            modelContext.delete(conversation)
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let providerStore: ProviderStore

    private var provider: ConfiguredProvider? {
        providerStore.provider(withID: conversation.providerID)
    }

    var body: some View {
        HStack(spacing: 12) {
            ProviderLogoView(
                logoAssetName: provider?.logoAssetName,
                symbolName: provider?.symbolName ?? "questionmark.circle",
                tint: provider.map { Color(hex: $0.tint) } ?? .gray,
                size: 36,
                cornerRadius: 10
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Text(conversation.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                Text(conversation.lastMessagePreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(conversation.updatedAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityLabel(conversation.isPinned ? "Pinned, \(conversation.title)" : conversation.title)
    }
}

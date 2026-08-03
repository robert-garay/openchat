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

    private var filtered: [Conversation] {
        guard !searchText.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.lastMessagePreview.localizedCaseInsensitiveContains(searchText)
        }
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
                    Image(systemName: "line.2.horizontal")
                        .accessibilityLabel("Settings")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
    }

    private func delete(_ conversation: Conversation) {
        Haptics.light()
        withAnimation(Theme.springFast) {
            if selectedConversationID == conversation.id {
                selectedConversationID = nil
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
                Text(conversation.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
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
    }
}

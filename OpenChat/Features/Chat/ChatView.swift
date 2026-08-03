import SwiftUI
import SwiftData

struct ChatView: View {
    let conversation: Conversation

    @Environment(\.modelContext) private var modelContext
    @Environment(ProviderStore.self) private var providerStore
    @Environment(AgentDataSourceStore.self) private var dataSourceStore
    @State private var viewModel: ChatViewModel?
    @State private var showingModelPicker = false

    var body: some View {
        VStack(spacing: 0) {
            if let viewModel {
                messageList(viewModel: viewModel)
                MessageComposerView(
                    text: Bindable(viewModel).composerText,
                    isStreaming: viewModel.isStreaming,
                    onSend: viewModel.send,
                    onStop: viewModel.cancelStreaming
                )
            }
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let viewModel {
                    Button {
                        Haptics.light()
                        showingModelPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.currentModel?.displayName ?? "Choose Model")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingModelPicker) {
            if let viewModel {
                ModelPickerSheet(
                    currentProviderID: conversation.providerID,
                    currentModelID: conversation.modelID,
                    onSelect: viewModel.selectModel
                )
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ChatViewModel(
                    conversation: conversation,
                    modelContext: modelContext,
                    providerStore: providerStore,
                    dataSourceStore: dataSourceStore
                )
            }
        }
    }

    @ViewBuilder
    private func messageList(viewModel: ChatViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(conversation.sortedMessages) { message in
                        MessageBubbleView(
                            message: message,
                            providerTint: viewModel.currentProvider.map { Color(hex: $0.tint) } ?? .accentColor,
                            providerSymbol: viewModel.currentProvider?.symbolName ?? "sparkles",
                            providerLogoAssetName: viewModel.currentProvider?.logoAssetName,
                            onRetry: viewModel.regenerateLastReply
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation.messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: conversation.sortedMessages.last?.content) {
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastID = conversation.sortedMessages.last?.id else { return }
        if animated {
            withAnimation(Theme.springFast) { proxy.scrollTo(lastID, anchor: .bottom) }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

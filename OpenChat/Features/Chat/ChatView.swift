import SwiftUI
import SwiftData

struct ChatView: View {
    let conversation: Conversation
    var onToggleTemporary: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(ProviderStore.self) private var providerStore
    @Environment(AgentDataSourceStore.self) private var dataSourceStore
    @State private var viewModel: ChatViewModel?
    @State private var showingModelPicker = false

    var body: some View {
        VStack(spacing: 0) {
            if conversation.isTemporary {
                TemporaryChatBanner()
            }

            if let viewModel {
                messageList(viewModel: viewModel)
                MessageComposerView(
                    text: Bindable(viewModel).composerText,
                    attachments: Bindable(viewModel).pendingAttachments,
                    supportsVision: viewModel.supportsVision,
                    modelDisplayName: viewModel.currentModel?.displayName,
                    isStreaming: viewModel.isStreaming,
                    onSend: {
                        viewModel.send()
                    },
                    onStop: viewModel.cancelStreaming
                )
            }
        }
        .navigationTitle(conversation.isTemporary ? "Temporary Chat" : conversation.title)
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
                                .lineLimit(1)
                            ModelCapabilitySigns(
                                capabilities: viewModel.currentModel?.capabilities ?? [],
                                limit: 3
                            )
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            if conversation.messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        onToggleTemporary?()
                    } label: {
                        GhostIcon(size: 17, filled: conversation.isTemporary)
                            .foregroundStyle(conversation.isTemporary ? Color.accentColor : Color.primary)
                            .accessibilityLabel(conversation.isTemporary ? "Exit temporary chat" : "Temporary chat")
                            .accessibilityAddTraits(conversation.isTemporary ? .isSelected : [])
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
        .alert(
            "Images not supported",
            isPresented: Binding(
                get: { viewModel?.capabilityWarning != nil },
                set: { if !$0 { viewModel?.dismissCapabilityWarning() } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel?.dismissCapabilityWarning()
            }
        } message: {
            Text(viewModel?.capabilityWarning ?? "")
        }
        .task(id: conversation.id) {
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
                            pendingCalendarActions: viewModel.pendingCalendarActionsByMessageID[message.id] ?? [],
                            calendarActionStatus: viewModel.calendarActionStatusByMessageID[message.id],
                            isApplyingCalendarActions: viewModel.isApplyingCalendarActions,
                            onConfirmCalendarActions: {
                                viewModel.confirmCalendarActions(for: message.id)
                            },
                            onDismissCalendarActions: {
                                viewModel.dismissCalendarActions(for: message.id)
                            },
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
            .task(id: conversation.id) {
                await Task.yield()
                scrollToBottom(proxy: proxy, animated: false)
                try? await Task.sleep(for: .milliseconds(50))
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

private struct TemporaryChatBanner: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Temporary Chat")
                .font(.subheadline.weight(.semibold))
            Text("This chat won’t appear in history.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.contentPadding)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

import SwiftUI
import SwiftData

struct ChatView: View {
    let conversation: Conversation
    var onToggleTemporary: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(ProviderStore.self) private var providerStore
    @Environment(AgentDataSourceStore.self) private var dataSourceStore
    @Environment(WebSearchStore.self) private var webSearchStore
    @Environment(RulesStore.self) private var rulesStore
    @Environment(MemoryStore.self) private var memoryStore
    @Query(sort: \Skill.name) private var skills: [Skill]
    @State private var viewModel: ChatViewModel?
    @State private var composerText = ""
    @State private var showingModelPicker = false
    @State private var showingChatRules = false
    @State private var showingNewSkill = false

    var body: some View {
        VStack(spacing: 0) {
            if conversation.isTemporary {
                TemporaryChatBanner()
            }

            if let viewModel {
                messageList(viewModel: viewModel)
                MessageComposerView(
                    text: $composerText,
                    attachments: Bindable(viewModel).pendingAttachments,
                    supportsVision: viewModel.supportsVision,
                    modelDisplayName: viewModel.currentModel?.displayName,
                    isStreaming: viewModel.isStreaming,
                    canUseWebSearch: viewModel.canUseWebSearch,
                    isWebSearchArmed: viewModel.isWebSearchArmed,
                    webSearchProviders: viewModel.configuredWebSearchProviders,
                    selectedWebSearchProvider: viewModel.selectedWebSearchProvider,
                    webSearchProviderName: viewModel.webSearchProviderName,
                    webSearchLogoAssetName: viewModel.webSearchStoreActiveLogo,
                    webSearchSymbolName: viewModel.webSearchStoreActiveSymbol,
                    webSearchTintHex: viewModel.webSearchStoreActiveTint,
                    onSelectWebSearchProvider: viewModel.selectWebSearchProvider,
                    onDisableWebSearch: viewModel.disableWebSearchForChat,
                    showCompactChip: viewModel.canShowCompact,
                    canCompact: viewModel.canCompactConversation,
                    isCompacting: viewModel.isCompacting,
                    onCompact: viewModel.compactConversation,
                    skills: skills.map(SkillMatchable.init(skill:)),
                    onSend: {
                        viewModel.send(text: composerText)
                        composerText = ""
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
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if conversation.messages.isEmpty {
                        Button {
                            Haptics.light()
                            onToggleTemporary?()
                        } label: {
                            GhostIcon(size: 17, filled: conversation.isTemporary)
                                .foregroundStyle(conversation.isTemporary ? Color.accentColor : Color.primary)
                                .accessibilityLabel(conversation.isTemporary ? "Exit temporary chat" : "Temporary chat")
                                .accessibilityAddTraits(conversation.isTemporary ? .isSelected : AccessibilityTraits())
                        }
                    }

                    Button {
                        Haptics.light()
                        showingChatRules = true
                    } label: {
                        Image(systemName: "text.alignleft")
                            .accessibilityLabel("Chat rules")
                    }

                    Button {
                        Haptics.light()
                        showingNewSkill = true
                    } label: {
                        Image(systemName: "bolt.badge.plus")
                            .accessibilityLabel("New Skill")
                    }
                }
            }
        }
        .sheet(isPresented: $showingChatRules) {
            ChatRulesSheet(conversation: conversation)
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
        .sheet(isPresented: $showingNewSkill) {
            SkillEditorView(skill: nil, createdFromChatID: conversation.id)
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
        .alert(
            "Switch model?",
            isPresented: Binding(
                get: { viewModel?.pendingModelSwitch != nil },
                set: { if !$0 { viewModel?.cancelPendingModelSwitch() } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                viewModel?.cancelPendingModelSwitch()
            }
            Button("Switch") {
                viewModel?.confirmPendingModelSwitch()
            }
        } message: {
            Text(viewModel?.pendingModelSwitch?.message ?? "")
        }
        .overlay(alignment: .top) {
            if let viewModel, let message = viewModel.compactStatusMessage {
                CompactStatusToast(message: message)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(2.5))
                            viewModel.dismissCompactStatus()
                        }
                    }
            }
        }
        .animation(Theme.springFast, value: viewModel?.compactStatusMessage)
        .task(id: conversation.id) {
            if viewModel == nil {
                viewModel = ChatViewModel(
                    conversation: conversation,
                    modelContext: modelContext,
                    providerStore: providerStore,
                    dataSourceStore: dataSourceStore,
                    webSearchStore: webSearchStore,
                    rulesStore: rulesStore,
                    memoryStore: memoryStore
                )
            }
        }
        .onDisappear {
            viewModel?.cancelStreaming()
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
                            isStreaming: message.isStreaming,
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
                            pendingMemoryProposals: viewModel.pendingMemoryProposalsByMessageID[message.id] ?? [],
                            memoryActionStatus: viewModel.memoryActionStatusByMessageID[message.id],
                            onConfirmMemoryProposals: {
                                viewModel.confirmMemoryProposals(for: message.id)
                            },
                            onDismissMemoryProposals: {
                                viewModel.dismissMemoryProposals(for: message.id)
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
                throttledScrollToBottom(proxy: proxy)
            }
            .task(id: conversation.id) {
                await Task.yield()
                scrollToBottom(proxy: proxy, animated: false)
                try? await Task.sleep(for: .milliseconds(50))
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    @State private var scrollThrottleTask: Task<Void, Never>?

    private func throttledScrollToBottom(proxy: ScrollViewProxy) {
        scrollThrottleTask?.cancel()
        scrollThrottleTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            scrollToBottom(proxy: proxy)
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

private struct CompactStatusToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
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

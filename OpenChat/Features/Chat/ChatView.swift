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
    @State private var showingModelPicker = false
    @State private var showingChatRules = false
    @State private var showingNewSkill = false
    @State private var stickToBottom = true

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
                        stickToBottom = true
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
    }

    @ViewBuilder
    private func messageList(viewModel: ChatViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(conversation.sortedMessages) { message in
                        let messageProvider = viewModel.provider(for: message)
                        MessageBubbleView(
                            message: message,
                            providerTint: messageProvider.map { Color(hex: $0.tint) } ?? .accentColor,
                            providerSymbol: messageProvider?.symbolName ?? "sparkles",
                            providerLogoAssetName: messageProvider?.logoAssetName,
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

                    Color.clear
                        .frame(height: 1)
                        .id(ChatScrollAnchor.bottom)
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .modifier(ChatStickToBottomModifier(stickToBottom: $stickToBottom))
            .overlay(alignment: .bottomTrailing) {
                if !stickToBottom && !conversation.sortedMessages.isEmpty {
                    jumpToLatestButton {
                        stickToBottom = true
                        Haptics.light()
                        scrollToBottom(proxy: proxy)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .animation(Theme.springFast, value: stickToBottom)
            .onChange(of: conversation.messages.count) {
                if stickToBottom {
                    scrollToBottom(proxy: proxy)
                }
            }
            .onChange(of: conversation.sortedMessages.last?.content) {
                if stickToBottom {
                    scrollToBottom(proxy: proxy)
                }
            }
            .task(id: conversation.id) {
                stickToBottom = true
                await Task.yield()
                scrollToBottom(proxy: proxy, animated: false)
                try? await Task.sleep(for: .milliseconds(50))
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    private func jumpToLatestButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.bar, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
        .accessibilityLabel("Jump to latest message")
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let action = {
            proxy.scrollTo(ChatScrollAnchor.bottom, anchor: .bottom)
        }
        if animated {
            withAnimation(Theme.springFast, action)
        } else {
            action()
        }
    }
}

private enum ChatScrollAnchor {
    static let bottom = "chat-bottom-anchor"
}

/// ChatGPT-style stick-to-bottom: follow streaming output while near the end;
/// scrolling up freezes the viewport; returning near the end resumes follow.
private struct ChatStickToBottomModifier: ViewModifier {
    @Binding var stickToBottom: Bool
    @State private var isUserScrolling = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollPhaseChange { _, phase in
                    // Ignore .animating so programmatic follow-scrolls do not detach.
                    switch phase {
                    case .tracking, .interacting, .decelerating:
                        isUserScrolling = true
                    default:
                        isUserScrolling = false
                    }
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
                    return visibleBottom >= geometry.contentSize.height - 80
                } action: { _, isNearBottom in
                    if isNearBottom {
                        stickToBottom = true
                    } else if isUserScrolling {
                        // Only detach on user-driven scroll so content growth
                        // during streaming does not break follow mode.
                        stickToBottom = false
                    }
                }
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        // Finger down → content moves up → reading older messages.
                        if value.translation.height > 12 {
                            stickToBottom = false
                        }
                    }
            )
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

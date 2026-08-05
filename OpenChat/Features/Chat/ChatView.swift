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
    /// Shared with the message list so Send re-attaches follow-to-bottom.
    @State private var stickToBottom = true

    var body: some View {
        VStack(spacing: 0) {
            if conversation.isTemporary {
                TemporaryChatBanner()
            }

            if let viewModel {
                // Isolated so composer keystrokes do not rebuild the message list.
                ChatMessageListView(
                    conversation: conversation,
                    viewModel: viewModel,
                    stickToBottom: $stickToBottom
                )

                ChatComposerHost(
                    viewModel: viewModel,
                    skills: skills,
                    onSend: {
                        stickToBottom = true
                        viewModel.send()
                    }
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
}

// MARK: - Composer host (isolates composerText observation)

/// Owns bindings into `ChatViewModel` composer state so keystrokes do not
/// invalidate `ChatMessageListView` or the surrounding `ChatView` chrome.
private struct ChatComposerHost: View {
    @Bindable var viewModel: ChatViewModel
    let skills: [Skill]
    let onSend: () -> Void

    var body: some View {
        MessageComposerView(
            text: $viewModel.composerText,
            attachments: $viewModel.pendingAttachments,
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
            onSend: onSend,
            onStop: viewModel.cancelStreaming
        )
    }
}

// MARK: - Message list

private struct ChatMessageListView: View {
    let conversation: Conversation
    let viewModel: ChatViewModel
    @Binding var stickToBottom: Bool

    /// True while the user is dragging/decelerating the message list.
    @State private var isInteractivelyScrolling = false
    @State private var followScrollTask: Task<Void, Never>?
    /// Last observed content height — used to re-pin after tall markdown lays out.
    @State private var lastContentHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // VStack (not LazyVStack): LazyVStack + scrollTo bottom leaves a blank
                // viewport for tall messages until the user scrolls and forces materialization.
                VStack(alignment: .leading, spacing: 18) {
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
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ChatContentHeightKey.self,
                            value: geometry.size.height
                        )
                    }
                )
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onPreferenceChange(ChatContentHeightKey.self) { height in
                handleContentHeightChange(height, proxy: proxy)
            }
            .modifier(
                ChatStickToBottomModifier(
                    stickToBottom: $stickToBottom,
                    isInteractivelyScrolling: $isInteractivelyScrolling
                )
            )
            .overlay(alignment: .bottomTrailing) {
                if !stickToBottom && !conversation.sortedMessages.isEmpty {
                    jumpToLatestButton {
                        stickToBottom = true
                        isInteractivelyScrolling = false
                        Haptics.light()
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .animation(Theme.springFast, value: stickToBottom)
                }
            }
            .onChange(of: conversation.messages.count) {
                scheduleFollowScroll(proxy: proxy)
            }
            .onChange(of: conversation.sortedMessages.last?.content) {
                scheduleFollowScroll(proxy: proxy)
            }
            .onChange(of: isInteractivelyScrolling) { _, scrolling in
                if scrolling {
                    followScrollTask?.cancel()
                    followScrollTask = nil
                }
            }
            .task(id: conversation.id) {
                stickToBottom = true
                isInteractivelyScrolling = false
                lastContentHeight = 0
                followScrollTask?.cancel()
                // Yield so the first layout pass can size tall markdown before pinning.
                await Task.yield()
                scrollToBottom(proxy: proxy, animated: false)
                for delay in [50, 150, 350] as [UInt64] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    guard !Task.isCancelled, stickToBottom, !isInteractivelyScrolling else { return }
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
        }
    }

    private func handleContentHeightChange(_ height: CGFloat, proxy: ScrollViewProxy) {
        guard height > lastContentHeight + 1 else {
            lastContentHeight = max(lastContentHeight, height)
            return
        }
        lastContentHeight = height
        scheduleFollowScroll(proxy: proxy)
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

    /// Pins to the latest content while following. Coalesces rapid stream tokens
    /// and never animates — animated scrollTo fights the user's pan gesture.
    private func scheduleFollowScroll(proxy: ScrollViewProxy) {
        guard stickToBottom, !isInteractivelyScrolling else { return }
        followScrollTask?.cancel()
        followScrollTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, stickToBottom, !isInteractivelyScrolling else { return }
            scrollToBottom(proxy: proxy, animated: false)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(ChatScrollAnchor.bottom, anchor: .bottom)
        }
        if animated {
            withAnimation(Theme.springFast, action)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, action)
        }
    }
}

private enum ChatScrollAnchor {
    static let bottom = "chat-bottom-anchor"
}

/// ChatGPT-style stick-to-bottom:
/// - Suppress follow for the whole user drag/deceleration so pans are not yanked
/// - Detach when the user scrolls away from the bottom
/// - Re-attach when they return near the bottom
private struct ChatStickToBottomModifier: ViewModifier {
    @Binding var stickToBottom: Bool
    @Binding var isInteractivelyScrolling: Bool

    private let attachThreshold: CGFloat = 48
    private let detachThreshold: CGFloat = 72

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollPhaseChange { _, phase in
                    switch phase {
                    case .tracking, .interacting, .decelerating:
                        isInteractivelyScrolling = true
                    default:
                        isInteractivelyScrolling = false
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height
                        - geometry.contentOffset.y
                        - geometry.containerSize.height
                } action: { _, distanceFromBottom in
                    if distanceFromBottom <= attachThreshold {
                        stickToBottom = true
                    } else if isInteractivelyScrolling, distanceFromBottom > detachThreshold {
                        stickToBottom = false
                    }
                }
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isInteractivelyScrolling = true
                        // Finger down → reading older messages → detach follow.
                        if value.translation.height > 8 {
                            stickToBottom = false
                        }
                    }
                    .onEnded { _ in
                        isInteractivelyScrolling = false
                    }
            )
        }
    }
}

private struct ChatContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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

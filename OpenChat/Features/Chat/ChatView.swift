import SwiftUI
import SwiftData

struct ChatView: View {
    let conversation: Conversation
    var onToggleTemporary: (() -> Void)?
    var onShowHistory: (() -> Void)?
    var isHistoryDrawerOpen: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(ProviderStore.self) private var providerStore
    @Environment(AgentDataSourceStore.self) private var dataSourceStore
    @Environment(WebSearchStore.self) private var webSearchStore
    @Environment(RulesStore.self) private var rulesStore
    @Environment(MemoryStore.self) private var memoryStore
    @Environment(SkillsStore.self) private var skillsStore
    @Query(sort: \Skill.name) private var skills: [Skill]
    @State private var viewModel: ChatViewModel?
    @State private var showingModelPicker = false
    @State private var showingNewSkill = false
    /// Shared with the message list so Send re-attaches follow-to-bottom.
    @State private var stickToBottom = true

    var body: some View {
        VStack(spacing: 0) {
            if conversation.isTemporary {
                TemporaryChatBanner()
            }

            if let viewModel {
                ZStack {
                    ChatMessageListView(
                        conversation: conversation,
                        viewModel: viewModel,
                        stickToBottom: $stickToBottom
                    )

                    if conversation.sortedMessages.isEmpty {
                        WelcomeOverlay()
                    }
                }

                ChatComposerHost(
                    viewModel: viewModel,
                    skills: skillsStore.isEnabled ? SkillResolver.withBuiltIns(skills.map(SkillMatchable.init(skill:))) : [],
                    hasChatRules: !conversation.systemPrompt
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty,
                    canUseChatRules: rulesStore.useChatRules,
                    conversation: conversation,
                    isFocused: Binding(
                        get: { !isHistoryDrawerOpen },
                        set: { _ in }
                    ),
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
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Haptics.light()
                    onShowHistory?()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chat history")
            }

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
                                .truncationMode(.tail)
                                .frame(maxWidth: conversation.messages.isEmpty ? 180 : 240)
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
                if conversation.messages.isEmpty {
                    Button {
                        Haptics.light()
                        onToggleTemporary?()
                    } label: {
                        GhostIcon(size: 22, filled: conversation.isTemporary)
                            .foregroundStyle(conversation.isTemporary ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(conversation.isTemporary ? "Exit temporary chat" : "Temporary chat")
                    .accessibilityAddTraits(conversation.isTemporary ? .isSelected : AccessibilityTraits())
                }
            }
        }
        .toolbar(isHistoryDrawerOpen ? .hidden : .visible, for: .navigationBar)
        .onChange(of: isHistoryDrawerOpen) { _, isOpen in
            if isOpen {
                #if canImport(UIKit)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
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
        .fullScreenCover(item: Binding(
            get: { viewModel?.editingMessage },
            set: { if $0 == nil { viewModel?.cancelEditing() } }
        )) { message in
            if let viewModel {
                EditMessageView(
                    message: message,
                    supportsVision: viewModel.supportsVision,
                    modelDisplayName: viewModel.currentModel?.displayName,
                    onCancel: {
                        viewModel.cancelEditing()
                    },
                    onSave: { newText, attachments in
                        viewModel.saveEdit(message, newText: newText, attachments: attachments)
                    }
                )
            }
        }
        .task(id: conversation.id) {
            bindViewModel()
        }
        .onDisappear {
            BackgroundGenerationService.shared.clearVisibleConversationID(ifEquals: conversation.id)
        }
        .onChange(of: viewModel?.composerText) { _, _ in
            viewModel?.persistComposerState()
        }
        .onChange(of: viewModel?.pendingAttachments) { _, _ in
            viewModel?.persistComposerState()
        }
        .onChange(of: viewModel?.selectedWebSearchProvider) { _, _ in
            viewModel?.persistComposerState()
        }
        .onChange(of: viewModel?.effortLevel) { _, _ in
            viewModel?.persistComposerState()
        }
        .onChange(of: viewModel?.isReasoningEnabled) { _, _ in
            viewModel?.persistComposerState()
        }
    }

    private func bindViewModel() {
        if viewModel == nil || viewModel?.conversation.id != conversation.id {
            viewModel = ChatViewModel(
                conversation: conversation,
                modelContext: modelContext,
                providerStore: providerStore,
                dataSourceStore: dataSourceStore,
                webSearchStore: webSearchStore,
                rulesStore: rulesStore,
                memoryStore: memoryStore,
                skillsStore: skillsStore
            )
        }
        BackgroundGenerationService.shared.setVisibleConversationID(conversation.id)
        viewModel?.markAllRead()
    }
}

// MARK: - Composer host (isolates composerText observation)

/// Owns bindings into `ChatViewModel` composer state so keystrokes do not
/// invalidate `ChatMessageListView` or the surrounding `ChatView` chrome.
private struct ChatComposerHost: View {
    @Bindable var viewModel: ChatViewModel
    let skills: [SkillMatchable]
    var hasChatRules: Bool = false
    var canUseChatRules: Bool = true
    var conversation: Conversation? = nil
    var isFocused: Binding<Bool> = .constant(false)
    let onSend: () -> Void

    var body: some View {
        MessageComposerView(
            text: $viewModel.composerText,
            attachments: $viewModel.pendingAttachments,
            documentAttachments: $viewModel.pendingDocumentAttachments,
            supportsVision: viewModel.supportsVision,
            supportsFiles: viewModel.supportsFiles,
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
            hasChatRules: hasChatRules,
            canUseChatRules: canUseChatRules,
            conversation: conversation,
            skills: skills,
            effortLevel: $viewModel.effortLevel,
            isReasoningEnabled: $viewModel.isReasoningEnabled,
            isFocused: isFocused,
            supportsEffort: viewModel.supportsEffort,
            supportedEffortLevels: viewModel.pickerEffortLevels,
            hasSeparateThinkingToggle: viewModel.hasSeparateThinkingToggle,
            onSetEffortLevel: viewModel.setEffortLevel,
            onSend: onSend,
            onStop: viewModel.cancelStreaming
        )
        .disabled(viewModel.editingMessageID != nil)
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
                    let sortedMessages = conversation.sortedMessages
                    let lastMessageID = sortedMessages.last?.id
                    ForEach(sortedMessages) { message in
                        MessageBubbleView(
                            message: message,
                            conversation: conversation,
                            pendingCalendarActions: viewModel.pendingCalendarActionsByMessageID[message.id] ?? [],
                            calendarActionStatus: viewModel.calendarActionStatusByMessageID[message.id],
                            isApplyingCalendarActions: viewModel.isApplyingCalendarActions,
                            onConfirmCalendarActions: {
                                Task { await viewModel.confirmCalendarActions(for: message.id) }
                            },
                            onDismissCalendarActions: {
                                viewModel.dismissCalendarActions(for: message.id)
                            },
                            pendingRemindersActions: viewModel.pendingRemindersActionsByMessageID[message.id] ?? [],
                            remindersActionStatus: viewModel.remindersActionStatusByMessageID[message.id],
                            isApplyingRemindersActions: viewModel.isApplyingRemindersActions,
                            onConfirmRemindersActions: {
                                Task { await viewModel.confirmRemindersActions(for: message.id) }
                            },
                            onDismissRemindersActions: {
                                viewModel.dismissRemindersActions(for: message.id)
                            },
                            pendingContactsActions: viewModel.pendingContactsActionsByMessageID[message.id] ?? [],
                            contactsActionStatus: viewModel.contactsActionStatusByMessageID[message.id],
                            isApplyingContactsActions: viewModel.isApplyingContactsActions,
                            onConfirmContactsActions: {
                                Task { await viewModel.confirmContactsActions(for: message.id) }
                            },
                            onDismissContactsActions: {
                                viewModel.dismissContactsActions(for: message.id)
                            },
                            pendingMemoryProposals: viewModel.pendingMemoryProposalsByMessageID[message.id] ?? [],
                            memoryActionStatus: viewModel.memoryActionStatusByMessageID[message.id],
                            onConfirmMemoryProposals: {
                                viewModel.confirmMemoryProposals(for: message.id)
                            },
                            onDismissMemoryProposals: {
                                viewModel.dismissMemoryProposals(for: message.id)
                            },
                            pendingSkillProposals: viewModel.pendingSkillProposalsByMessageID[message.id] ?? [],
                            skillActionStatus: viewModel.skillActionStatusByMessageID[message.id],
                            onDismissSkillProposals: {
                                viewModel.dismissSkillProposals(for: message.id)
                            },
                            onSkillProposalSaved: {
                                viewModel.clearSkillProposalAfterReview(for: message.id)
                            },
                            pendingRuleProposals: viewModel.pendingRuleProposalsByMessageID[message.id] ?? [],
                            ruleActionStatus: viewModel.ruleActionStatusByMessageID[message.id],
                            onDismissRuleProposals: {
                                viewModel.dismissRuleProposals(for: message.id)
                            },
                            onRuleProposalSaved: { proposalID in
                                viewModel.clearRuleProposalAfterReview(for: message.id, proposalID: proposalID)
                            },
                            isLastMessage: message.id == lastMessageID,
                            onRetry: viewModel.regenerateLastReply,
                            canEdit: !viewModel.isStreaming,
                            onBeginEdit: {
                                viewModel.beginEditing(message)
                            }
                        )
                        .id(message.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(ChatScrollAnchor.bottom)
                }
                .padding(.horizontal, Theme.chatHorizontalPadding)
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
            // Use a larger minimum distance so the long-press gesture for text
            // selection can start before the drag gesture begins.
            content.simultaneousGesture(
                DragGesture(minimumDistance: 12)
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
    static var defaultValue: CGFloat { 0 }
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

private struct WelcomeOverlay: View {
    var body: some View {
        OpenChatLogoView(size: 72)
    }
}

private struct TemporaryChatBanner: View {
    var body: some View {
        Text("Temporary Chat")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.contentPadding)
            .padding(.vertical, 10)
            .background(.bar)
    }
}

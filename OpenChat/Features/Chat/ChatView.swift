import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct ChatView: View {
    let conversation: Conversation

    @Environment(\.modelContext) private var modelContext
    @Environment(ProviderStore.self) private var providerStore
    @Environment(AgentDataSourceStore.self) private var dataSourceStore
    @State private var viewModel: ChatViewModel?
    @State private var showingModelPicker = false
    @State private var stickToBottom = true
    @FocusState private var composerFocused: Bool

    var body: some View {
        Group {
            if let viewModel {
                messageList(viewModel: viewModel)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        MessageComposerView(
                            text: Bindable(viewModel).composerText,
                            attachments: Bindable(viewModel).pendingAttachments,
                            supportsVision: viewModel.supportsVision,
                            modelDisplayName: viewModel.currentModel?.displayName,
                            isStreaming: viewModel.isStreaming,
                            isFocused: $composerFocused,
                            onSend: {
                                stickToBottom = true
                                viewModel.send()
                            },
                            onStop: viewModel.cancelStreaming
                        )
                    }
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
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    composerFocused = false
                }
                .fontWeight(.semibold)
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
        .onAppear {
            if viewModel == nil {
                viewModel = ChatViewModel(
                    conversation: conversation,
                    modelContext: modelContext,
                    providerStore: providerStore,
                    dataSourceStore: dataSourceStore
                )
            }
            if conversation.sortedMessages.isEmpty {
                composerFocused = true
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

                    Color.clear
                        .frame(height: 1)
                        .id(ChatScrollAnchor.bottom)
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .modifier(ChatNearBottomStickModifier(stickToBottom: $stickToBottom))
            .overlay(alignment: .bottomTrailing) {
                if !stickToBottom && !conversation.sortedMessages.isEmpty {
                    jumpToLatestButton {
                        stickToBottom = true
                        Haptics.light()
                        scrollToBottom(proxy: proxy)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                }
            }
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
            .onChange(of: composerFocused) { _, focused in
                guard focused, stickToBottom else { return }
                scrollToBottom(proxy: proxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
                guard stickToBottom else { return }
                DispatchQueue.main.async {
                    scrollToBottom(proxy: proxy)
                }
            }
            .onAppear {
                stickToBottom = true
                scrollToBottom(proxy: proxy, animated: false)
            }
            .task(id: conversation.id) {
                stickToBottom = true
                await Task.yield()
                scrollToBottom(proxy: proxy, animated: false)
                try? await Task.sleep(for: .milliseconds(100))
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

/// Tracks whether the user is near the latest messages. Uses the iOS 18 scroll
/// geometry API when available; on iOS 17 the chat stays stuck to the bottom.
private struct ChatNearBottomStickModifier: ViewModifier {
    @Binding var stickToBottom: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
                return visibleBottom >= geometry.contentSize.height - 120
            } action: { _, isNearBottom in
                if isNearBottom {
                    stickToBottom = true
                } else if stickToBottom {
                    stickToBottom = false
                }
            }
        } else {
            content
        }
    }
}

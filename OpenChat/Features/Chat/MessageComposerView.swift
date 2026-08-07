import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MessageComposerView: View {
    @Binding var text: String
    @Binding var attachments: [ChatImageAttachment]
    let supportsVision: Bool
    let modelDisplayName: String?
    let isStreaming: Bool
    var canUseWebSearch: Bool = false
    var isWebSearchArmed: Bool = false
    var webSearchProviders: [WebSearchProviderKind] = []
    var selectedWebSearchProvider: WebSearchProviderKind? = nil
    var webSearchProviderName: String = "Search"
    var webSearchLogoAssetName: String? = nil
    var webSearchSymbolName: String = "globe"
    var webSearchTintHex: String = "007AFF"
    var onSelectWebSearchProvider: ((WebSearchProviderKind) -> Void)? = nil
    var onDisableWebSearch: (() -> Void)? = nil
    var showCompactChip: Bool = false
    var canCompact: Bool = false
    var isCompacting: Bool = false
    var onCompact: (() -> Void)? = nil
    /// When true, rules chip uses accent (conversation has a non-empty system prompt).
    var hasChatRules: Bool = false
    var canUseChatRules: Bool = true
    var conversation: Conversation? = nil
    var skills: [SkillMatchable] = []
    let onSend: () -> Void
    let onStop: () -> Void

    @State private var showingWebSearchDisabledAlert = false
    @State private var showingChatRules = false

    /// Avoid `trimmingCharacters` on huge pastes — that allocates and scans the full string.
    private var canSend: Bool {
        !attachments.isEmpty || text.contains { !$0.isWhitespace }
    }

    private var slashQuery: String? { SkillResolver.slashQuery(from: text) }
    private var matchingSkills: [SkillMatchable] {
        guard let slashQuery else { return [] }
        return SkillResolver.filter(skills, query: slashQuery)
    }
    private var showSkillPicker: Bool { slashQuery != nil && !matchingSkills.isEmpty }

    var body: some View {
        AttachmentComposerBox(
            attachments: $attachments,
            supportsVision: supportsVision,
            modelDisplayName: modelDisplayName
        ) { onPasteImages in
            composerField(onPasteImages: onPasteImages)
        } buttons: {
            webSearchButton
            if canUseChatRules {
                chatRulesButton
            }
            compactButton
            Spacer(minLength: 0)
            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .alert("Web search unavailable", isPresented: $showingWebSearchDisabledAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add a search API key in Settings → Web Search, then pick a provider from the web search button.")
        }
    }

    private func composerField(onPasteImages: @escaping ([UIImage]) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showSkillPicker {
                SkillPickerDropdown(skills: matchingSkills) { skill in
                    text = SkillResolver.applySelection(skill: skill, to: text)
                    Haptics.light()
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
            #if canImport(UIKit)
            ComposerTextView(
                text: $text,
                placeholder: "Message",
                minHeight: 22,
                maxHeight: 120,
                onPasteImages: onPasteImages
            )
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            // Explicit vertical sizing — `.frame(minHeight:maxHeight:)` expands to
            // maxHeight inside this VStack even when the field is empty.
            .fixedSize(horizontal: false, vertical: true)
            #else
            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .onSubmit(submitIfPossible)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            #endif
        }
        .animation(Theme.springFast, value: showSkillPicker)
    }

    /// Explicit web search provider menu order: Tavily first, Exa second, then any remaining providers in their original order, with Off at the bottom.
    private var orderedWebSearchProviders: [WebSearchProviderKind] {
        let prioritized: [WebSearchProviderKind] = [.tavily, .exa]
        let prioritizedProviders = prioritized.filter { webSearchProviders.contains($0) }
        let remainingProviders = webSearchProviders.filter { !prioritized.contains($0) }
        return prioritizedProviders + remainingProviders
    }

    private var webSearchButton: some View {
        Group {
            if canUseWebSearch {
                Menu {
                    ForEach(orderedWebSearchProviders) { provider in
                        Button {
                            onSelectWebSearchProvider?(provider)
                        } label: {
                            HStack(spacing: 12) {
                                ProviderLogoView(
                                    logoAssetName: provider.logoAssetName,
                                    symbolName: provider.symbolName,
                                    tint: Color(hex: provider.tintHex),
                                    size: 22,
                                    cornerRadius: 6
                                )
                                Text(provider.displayName)
                                Spacer(minLength: 12)
                                if isWebSearchArmed && selectedWebSearchProvider == provider {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }

                    Button {
                        onDisableWebSearch?()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "globe")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(.secondaryLabel))
                                .frame(width: 22, height: 22)
                                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text("Off")
                            Spacer(minLength: 12)
                            if !isWebSearchArmed {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                } label: {
                    webSearchIcon
                }
                .accessibilityLabel(isWebSearchArmed ? "Web search on" : "Web search off")
                .accessibilityHint(
                    isWebSearchArmed
                        ? "Using \(webSearchProviderName). Choose another provider or turn web search off."
                        : "Choose a search provider for this chat."
                )
            } else {
                Button {
                    Haptics.warning()
                    showingWebSearchDisabledAlert = true
                } label: {
                    webSearchIcon
                }
                .accessibilityLabel("Web search off")
                .accessibilityHint("Add a search API key in Settings")
            }
        }
        .animation(Theme.springFast, value: isWebSearchArmed)
        .animation(Theme.springFast, value: selectedWebSearchProvider)
    }

    private var webSearchIcon: some View {
        ZStack {
            if isWebSearchArmed {
                ProviderLogoView(
                    logoAssetName: webSearchLogoAssetName,
                    symbolName: webSearchSymbolName,
                    tint: Color(hex: webSearchTintHex),
                    size: 28,
                    cornerRadius: 8
                )
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
                    .opacity(canUseWebSearch ? 1 : 0.85)
            }
        }
        .frame(width: 34, height: 34)
    }

    private var chatRulesButton: some View {
        Button {
            Haptics.light()
            showingChatRules = true
        } label: {
            Image(systemName: "text.alignleft")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(hasChatRules ? Color.accentColor : Color(.tertiaryLabel))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Chat rules")
        .accessibilityHint(
            hasChatRules
                ? "Edit instructions for this conversation"
                : "Add instructions for this conversation"
        )
        .animation(Theme.springFast, value: hasChatRules)
        .sheet(isPresented: $showingChatRules) {
            if let conversation {
                ChatRulesSheet(conversation: conversation)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private var compactButton: some View {
        if showCompactChip {
            Menu {
                Button(role: .destructive) {
                    Haptics.light()
                    onCompact?()
                } label: {
                    Label("Compact conversation", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!canCompact || isCompacting)
            } label: {
                Group {
                    if isCompacting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(canCompact ? Color.primary : Color(.tertiaryLabel))
                    }
                }
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
            }
            .disabled(isCompacting)
            .accessibilityLabel("Compact conversation")
            .accessibilityHint(
                canCompact
                    ? "Summarize older messages to save context"
                    : "Not enough messages to compact"
            )
        }
    }

    private var sendButton: some View {
        Button(action: primaryAction) {
            Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, primaryButtonColor)
        }
        .disabled(!isStreaming && !canSend)
        .animation(Theme.springFast, value: canSend)
        .animation(Theme.springFast, value: isStreaming)
    }

    private var primaryButtonColor: Color {
        if isStreaming { return .red }
        return canSend ? .accentColor : Color(.tertiaryLabel)
    }

    private func primaryAction() {
        if isStreaming {
            Haptics.medium()
            onStop()
        } else {
            submitIfPossible()
        }
    }

    private func submitIfPossible() {
        guard canSend else { return }
        Haptics.light()
        onSend()
    }
}

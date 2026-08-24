import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MessageComposerView: View {
    @Binding var text: String
    @Binding var attachments: [ChatImageAttachment]
    @Binding var documentAttachments: [ChatDocumentAttachment]
    let supportsVision: Bool
    let supportsFiles: Bool
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
    var canUseVoiceMode: Bool = false
    var onStartVoiceMode: (() -> Void)? = nil
    @Binding var effortLevel: EffortLevel
    @Binding var isReasoningEnabled: Bool
    var isFocused: Binding<Bool> = .constant(false)
    var supportsEffort: Bool = false
    var supportedEffortLevels: [EffortLevel] = []
    var hasSeparateThinkingToggle: Bool = false
    var onSetEffortLevel: ((EffortLevel) -> Void)? = nil
    let onSend: () -> Void
    let onStop: () -> Void

    @State private var showingWebSearchDisabledAlert = false
    @State private var showingChatRules = false
    @State private var showingEffortPicker = false

    /// The level shown in the gauge and sent to the API, clamped to the model's supported set.
    private var effectiveLevel: EffortLevel {
        guard supportsEffort, !supportedEffortLevels.isEmpty else { return .default }
        return supportedEffortLevels.contains(effortLevel) ? effortLevel : (supportedEffortLevels.last ?? .default)
    }

    /// Avoid `trimmingCharacters` on huge pastes — that allocates and scans the full string.
    private var canSend: Bool {
        !attachments.isEmpty || !documentAttachments.isEmpty || text.contains { !$0.isWhitespace }
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
            documentAttachments: $documentAttachments,
            supportsVision: supportsVision,
            supportsFiles: supportsFiles,
            modelDisplayName: modelDisplayName
        ) { onPasteImages, onPasteDocument in
            composerField(onPasteImages: onPasteImages, onPasteDocument: onPasteDocument)
        } buttons: {
            webSearchButton
            if canUseChatRules {
                chatRulesButton
            }
            compactButton
            Spacer(minLength: 0)
            if hasSeparateThinkingToggle {
                reasoningToggleButton
            }
            if supportsEffort && (!hasSeparateThinkingToggle || isReasoningEnabled) {
                effortButton
            }
            if canUseVoiceMode, !isStreaming, !canSend {
                voiceModeButton
            } else {
                sendButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .alert("Web search unavailable", isPresented: $showingWebSearchDisabledAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add a search API key in Settings → Web Search, then pick a provider from the web search button.")
        }
    }

    private func composerField(
        onPasteImages: @escaping ([UIImage]) -> Void,
        onPasteDocument: @escaping (Data, String?) -> Void
    ) -> some View {
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
                onPasteImages: onPasteImages,
                onPasteDocument: onPasteDocument,
                isFocused: isFocused
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

    private var webSearchButton: some View {
        Group {
            if canUseWebSearch {
                Menu {
                    // The composer sits at the bottom of the screen, so this menu always
                    // opens upward. UIKit keeps the first item closest to the button,
                    // which flips the visual top-to-bottom order — so the item order here
                    // is reversed to make "Off" land at the bottom and providers read in
                    // Settings order from top to bottom on screen.
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

                    ForEach(webSearchProviders.reversed()) { provider in
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
                } label: {
                    webSearchIcon
                }
                .accessibilityLabel(isWebSearchArmed ? "Web search on" : "Web search off")
                .accessibilityHint(
                    isWebSearchArmed
                        ? "Using \(webSearchProviderName). Choose another provider or turn web search off."
                        : "Choose a search provider for this chat."
                )
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

    private var reasoningToggleButton: some View {
        Button {
            Haptics.light()
            isReasoningEnabled.toggle()
        } label: {
            Image(systemName: isReasoningEnabled ? "brain.fill" : "brain")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isReasoningEnabled ? Color.accentColor : Color(.tertiaryLabel))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(isReasoningEnabled ? "Reasoning enabled" : "Reasoning disabled")
        .accessibilityHint("Toggle reasoning on or off")
    }

    private var effortButton: some View {
        Button {
            Haptics.light()
            showingEffortPicker = true
        } label: {
            EffortGaugeIcon(
                level: effectiveLevel,
                levels: supportedEffortLevels,
                color: effectiveLevel == .none ? Color(.tertiaryLabel) : Color.accentColor,
                size: 22
            )
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(effectiveLevel.accessibilityLabel)
        .accessibilityHint("Change reasoning effort level")
        .sheet(isPresented: $showingEffortPicker) {
            EffortLevelPicker(
                level: effectiveLevel,
                levels: supportedEffortLevels,
                onChange: { level in
                    effortLevel = level
                    onSetEffortLevel?(level)
                }
            )
            .presentationDetents([.height(220)])
            .presentationBackground(.bar)
        }
    }

    private var voiceModeButton: some View {
        Button {
            Haptics.light()
            onStartVoiceMode?()
        } label: {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
        }
        .accessibilityLabel("Start voice mode")
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

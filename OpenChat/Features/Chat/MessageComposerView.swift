import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CoreTransferable
#if canImport(UIKit)
import UIKit
#endif

private struct RawImageData: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            RawImageData(data: data)
        }
    }
}

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

    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showingVisionAlert = false
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var showingWebSearchDisabledAlert = false
    @State private var showingChatRules = false
    @State private var showingCompactConfirmation = false
    @State private var showingNotEnoughMessagesAlert = false
    #if canImport(UIKit)
    @State private var previewAttachment: ChatImageAttachment?
    #endif

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
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                attachmentStrip
            }

            composerField
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(.bar)
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoPickerItems, maxSelectionCount: 4, matching: .images)
        .onChange(of: photoPickerItems) { _, items in
            Task { await loadPickerItems(items) }
        }
        .onDrop(of: [UTType.image], isTargeted: nil) { providers in
            handleDropProviders(providers)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            #if canImport(UIKit)
            CameraPicker(isPresented: $showingCamera) { image in
                appendImage(image)
            }
            .ignoresSafeArea()
            #else
            Color.clear.onAppear { showingCamera = false }
            #endif
        }
        .alert("Images not supported", isPresented: $showingVisionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let modelDisplayName {
                Text("\(modelDisplayName) can’t process images. Choose a model marked with an eye to attach or paste photos.")
            } else {
                Text("This model can’t process images. Choose a model marked with an eye to attach or paste photos.")
            }
        }
        .alert("Web search unavailable", isPresented: $showingWebSearchDisabledAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add a search API key in Settings → Web Search, then pick a provider from the web search button.")
        }
        .confirmationDialog(
            "Compact conversation?",
            isPresented: $showingCompactConfirmation,
            titleVisibility: .visible
        ) {
            Button("Compact", role: .destructive) {
                onCompact?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Older messages will be summarized into context. Your most recent messages stay as-is in the chat.")
        }
        .alert("Not enough messages", isPresented: $showingNotEnoughMessagesAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Not enough messages to compact.")
        }
        #if canImport(UIKit)
        .fullScreenCover(item: $previewAttachment) { attachment in
            if let uiImage = UIImage(data: attachment.data) {
                ImagePreviewView(image: uiImage)
            }
        }
        #endif
    }

    private var composerField: some View {
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
                maxHeight: 120
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

            HStack(alignment: .center, spacing: 2) {
                plusMenuButton
                webSearchButton
                if canUseChatRules {
                    chatRulesButton
                }
                compactButton
                Spacer(minLength: 0)
                sendButton
            }
            .padding(.leading, 2)
            .padding(.trailing, 4)
            .padding(.bottom, 4)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(Theme.springFast, value: showSkillPicker)
    }

    private var plusMenuButton: some View {
        Menu {
            if CameraCaptureAvailability.isAvailable {
                Button {
                    requestCamera()
                } label: {
                    Label("Camera", systemImage: "camera")
                }
            }

            Button {
                requestPhotoLibrary()
            } label: {
                Label("Photos", systemImage: "photo")
            }

            Button(action: pasteFromClipboard) {
                Label("Paste Image", systemImage: "doc.on.clipboard")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Add")
        .accessibilityHint("Attach a photo or paste an image")
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
                    .presentationDetents([.height(340), .large])
                    .presentationCornerRadius(24)
            }
        }
    }

    @ViewBuilder
    private var compactButton: some View {
        if showCompactChip {
            Button(action: requestCompact) {
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

    private func requestCompact() {
        guard canCompact else {
            Haptics.warning()
            showingNotEnoughMessagesAlert = true
            return
        }
        showingCompactConfirmation = true
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

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        #if canImport(UIKit)
                        if let uiImage = UIImage(data: attachment.data) {
                            Button {
                                Haptics.light()
                                previewAttachment = attachment
                            } label: {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Preview image")
                        }
                        #endif
                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .offset(x: 4, y: -4)
                        .accessibilityLabel("Remove image")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }

    private var primaryButtonColor: Color {
        if isStreaming { return .red }
        return canSend ? .accentColor : Color(.tertiaryLabel)
    }

    private func requestPhotoLibrary() {
        guard supportsVision else {
            Haptics.warning()
            showingVisionAlert = true
            return
        }
        showingPhotoPicker = true
    }

    private func requestCamera() {
        guard supportsVision else {
            Haptics.warning()
            showingVisionAlert = true
            return
        }
        showingCamera = true
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

    private func pasteFromClipboard() {
        #if canImport(UIKit)
        guard supportsVision else {
            Haptics.warning()
            showingVisionAlert = true
            return
        }
        guard let image = UIPasteboard.general.image else { return }
        appendImage(image)
        #endif
    }

    private func handleDropProviders(_ providers: [NSItemProvider]) -> Bool {
        guard supportsVision else {
            Haptics.warning()
            showingVisionAlert = true
            return false
        }
        loadImages(from: providers)
        return true
    }

    private func loadImages(from providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    appendImageData(data)
                }
            }
        }
    }

    @MainActor
    private func loadPickerItems(_ items: [PhotosPickerItem]) async {
        guard supportsVision else {
            photoPickerItems = []
            showingVisionAlert = true
            return
        }
        for item in items {
            if let raw = try? await item.loadTransferable(type: RawImageData.self) {
                _ = appendImageData(raw.data)
            } else if let data = try? await item.loadTransferable(type: Data.self) {
                _ = appendImageData(data)
            }
        }
        photoPickerItems = []
    }

    @discardableResult
    private func appendImageData(_ data: Data) -> Bool {
        guard let attachment = ImageAttachmentEncoder.makeAttachment(from: data) else { return false }
        attachments.append(attachment)
        Haptics.light()
        return true
    }

    #if canImport(UIKit)
    private func appendImage(_ image: UIImage) {
        guard supportsVision else {
            Haptics.warning()
            showingVisionAlert = true
            return
        }
        guard let attachment = ImageAttachmentEncoder.makeAttachment(from: image) else { return }
        attachments.append(attachment)
        Haptics.light()
    }
    #endif
}

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
    let onSend: () -> Void
    let onStop: () -> Void

    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showingVisionAlert = false
    @State private var showingFilesAlert = false
    @State private var showingInvalidDocumentAlert = false
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var showingFileImporter = false
    @State private var showingWebSearchDisabledAlert = false
    @State private var showingChatRules = false
    #if canImport(UIKit)
    @State private var previewAttachment: ChatImageAttachment?
    @State private var previewDocument: ChatDocumentAttachment?
    #endif

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
        VStack(spacing: 0) {
            if !attachments.isEmpty || !documentAttachments.isEmpty {
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
        .onDrop(of: [UTType.image, UTType.pdf], isTargeted: nil) { providers in
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
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf]) { result in
            handleFileImporterResult(result)
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
        .alert("Documents not supported", isPresented: $showingFilesAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let modelDisplayName {
                Text("\(modelDisplayName) can't process documents. Choose a model marked with a doc icon to attach or paste PDFs.")
            } else {
                Text("This model can't process documents. Choose a model marked with a doc icon to attach or paste PDFs.")
            }
        }
        .alert("Web search unavailable", isPresented: $showingWebSearchDisabledAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add a search API key in Settings → Web Search, then pick a provider from the web search button.")
        }
        .alert("Couldn't attach file", isPresented: $showingInvalidDocumentAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Couldn't attach that file — PDFs only, up to 32MB.")
        }
        #if canImport(UIKit)
        .fullScreenCover(item: $previewAttachment) { attachment in
            if let uiImage = UIImage(data: attachment.data) {
                ImagePreviewView(image: uiImage)
            }
        }
        .fullScreenCover(item: $previewDocument) { attachment in
            DocumentPreviewView(attachment: attachment)
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
                maxHeight: 120,
                onPasteImages: handlePastedImages,
                onPasteDocument: handlePastedDocument
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

            Button {
                requestFiles()
            } label: {
                Label("Browse Files", systemImage: "doc")
            }

            Button(action: pasteDocumentFromClipboard) {
                Label("Paste Document", systemImage: "doc.badge.clock")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Add")
        .accessibilityHint("Attach a photo, PDF, or paste content")
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
                ForEach(documentAttachments) { document in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            Haptics.light()
                            previewDocument = document
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.accentColor)
                                Text(document.filename)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(Color.primary)
                                    .frame(maxWidth: 50)
                            }
                            .frame(width: 56, height: 56)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Preview document \(document.filename)")
                        Button {
                            documentAttachments.removeAll { $0.id == document.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .offset(x: 4, y: -4)
                        .accessibilityLabel("Remove document")
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

    private func requestFiles() {
        guard supportsFiles else {
            Haptics.warning()
            showingFilesAlert = true
            return
        }
        showingFileImporter = true
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

    private func pasteDocumentFromClipboard() {
        guard supportsFiles else {
            Haptics.warning()
            showingFilesAlert = true
            return
        }
        guard let data = UIPasteboard.general.data(forPasteboardType: UTType.pdf.identifier) else { return }
        let filename = UIPasteboard.general.itemProviders.first?.suggestedName ?? "Document.pdf"
        appendDocumentData(data, filename: filename)
    }

    private func handlePastedImages(_ images: [UIImage]) {
        #if canImport(UIKit)
        guard supportsVision else {
            Haptics.warning()
            showingVisionAlert = true
            return
        }
        for image in images {
            appendImage(image)
        }
        #endif
    }

    private func handlePastedDocument(_ data: Data, filename: String?) {
        guard supportsFiles else {
            Haptics.warning()
            showingFilesAlert = true
            return
        }
        appendDocumentData(data, filename: filename ?? "Document.pdf")
    }

    private func handleDropProviders(_ providers: [NSItemProvider]) -> Bool {
        let hasImage = providers.contains { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        let hasPDF = providers.contains { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }

        if hasImage {
            guard supportsVision else {
                Haptics.warning()
                showingVisionAlert = true
                return false
            }
            loadImages(from: providers)
        }
        if hasPDF {
            guard supportsFiles else {
                Haptics.warning()
                showingFilesAlert = true
                return false
            }
            loadDocuments(from: providers)
        }
        return hasImage || hasPDF
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

    private func loadDocuments(from providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            let suggestedName = provider.suggestedName
            provider.loadDataRepresentation(forTypeIdentifier: UTType.pdf.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    appendDocumentData(data, filename: suggestedName ?? "Document.pdf")
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

    @discardableResult
    private func appendDocumentData(_ data: Data, filename: String) -> Bool {
        guard let attachment = DocumentAttachmentEncoder.makeAttachment(from: data, filename: filename) else {
            Haptics.warning()
            showingInvalidDocumentAlert = true
            return false
        }
        documentAttachments.append(attachment)
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

    private func handleFileImporterResult(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        appendDocumentData(data, filename: url.lastPathComponent)
    }
}

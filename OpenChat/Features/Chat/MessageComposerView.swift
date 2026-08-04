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
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showingVisionAlert = false
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var showingWebSearchDisabledAlert = false
    @State private var showingWebSearchPicker = false

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || !attachments.isEmpty
    }

    private var pasteboardHasImage: Bool {
        #if canImport(UIKit)
        UIPasteboard.general.hasImages
        #else
        false
        #endif
    }

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
            Text("Add a search API key in Settings → Web Search, then pick a provider from the + menu.")
        }
    }

    private var composerField: some View {
        HStack(alignment: .bottom, spacing: 0) {
            plusMenuButton

            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .focused($isFocused)
                .onSubmit(submitIfPossible)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)

            if isWebSearchArmed {
                webSearchArmedChip
                    .padding(.bottom, 4)
            }

            sendButton
                .padding(.bottom, 2)
        }
        .padding(.leading, 2)
        .padding(.trailing, 4)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
            .disabled(!pasteboardHasImage)

            Divider()

            Button {
                // Let the menu dismiss before presenting the provider popover.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    openWebSearch()
                }
            } label: {
                Label(
                    isWebSearchArmed ? "Web Search · \(webSearchProviderName)" : "Web Search",
                    systemImage: "globe"
                )
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .padding(.bottom, 2)
        .accessibilityLabel("Add")
        .accessibilityHint("Attach a photo, paste an image, or turn on web search")
        .popover(isPresented: $showingWebSearchPicker, arrowEdge: .bottom) {
            WebSearchProviderPicker(
                providers: webSearchProviders,
                selectedProvider: isWebSearchArmed ? selectedWebSearchProvider : nil,
                onSelect: { provider in
                    showingWebSearchPicker = false
                    onSelectWebSearchProvider?(provider)
                },
                onDisable: {
                    showingWebSearchPicker = false
                    onDisableWebSearch?()
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var webSearchArmedChip: some View {
        Button {
            openWebSearch()
        } label: {
            ProviderLogoView(
                logoAssetName: webSearchLogoAssetName,
                symbolName: webSearchSymbolName,
                tint: Color(hex: webSearchTintHex),
                size: 26,
                cornerRadius: 7
            )
        }
        .accessibilityLabel("Web search on")
        .accessibilityHint("Using \(webSearchProviderName). Choose another provider or turn web search off.")
        .animation(Theme.springFast, value: selectedWebSearchProvider)
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
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    private func openWebSearch() {
        if canUseWebSearch {
            showingWebSearchPicker = true
        } else {
            Haptics.warning()
            showingWebSearchDisabledAlert = true
        }
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

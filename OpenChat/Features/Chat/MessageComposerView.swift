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
    var webSearchProviderName: String = "Search"
    var onToggleWebSearch: (() -> Void)? = nil
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showingVisionAlert = false
    @State private var showingPhotoPicker = false
    @State private var showingWebSearchDisabledAlert = false

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

            HStack(alignment: .bottom, spacing: 8) {
                attachButton
                webSearchButton

                TextField("Message", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .focused($isFocused)
                    .onSubmit(submitIfPossible)

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
            Text("Add a search API key in Settings → Web Search, enable it, and choose an active provider.")
        }
    }

    private var webSearchButton: some View {
        Button {
            if canUseWebSearch {
                onToggleWebSearch?()
            } else {
                Haptics.warning()
                showingWebSearchDisabledAlert = true
            }
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isWebSearchArmed ? Color.accentColor : Color(.tertiaryLabel))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .opacity(canUseWebSearch || isWebSearchArmed ? 1 : 0.85)
        }
        .accessibilityLabel(isWebSearchArmed ? "Web search on" : "Web search off")
        .accessibilityHint(
            canUseWebSearch
                ? "Uses \(webSearchProviderName). Tap to turn web search \(isWebSearchArmed ? "off" : "on") for this chat."
                : "Configure a search provider in Settings"
        )
        .animation(Theme.springFast, value: isWebSearchArmed)
    }

    private var attachButton: some View {
        Group {
            if supportsVision {
                Menu {
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                    Button(action: pasteFromClipboard) {
                        Label("Paste Image", systemImage: "doc.on.clipboard")
                    }
                    .disabled(!pasteboardHasImage)
                } label: {
                    attachIcon(active: true)
                }
            } else {
                Button {
                    Haptics.warning()
                    showingVisionAlert = true
                } label: {
                    attachIcon(active: false)
                }
            }
        }
        .accessibilityLabel("Attach")
        .accessibilityHint(supportsVision ? "Attach or paste an image" : "Current model does not support images")
    }

    private func attachIcon(active: Bool) -> some View {
        Image(systemName: "paperclip")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(active ? Color.accentColor : Color(.tertiaryLabel))
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
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
        guard let attachment = ImageAttachmentEncoder.makeAttachment(from: image) else { return }
        attachments.append(attachment)
        Haptics.light()
    }
    #endif
}

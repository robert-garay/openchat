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

/// Rounded composer box that owns image attachments: the thumbnail strip, the
/// plus menu (Camera / Photos / Paste Image), drag-and-drop, and paste.
///
/// Shared by the main composer and the edit screen, which differ only in what
/// they put in the two slots — the text field, and the buttons trailing the
/// plus menu (the host supplies its own `Spacer` and send button).
struct AttachmentComposerBox<Field: View, Buttons: View>: View {
    @Binding var attachments: [ChatImageAttachment]
    let supportsVision: Bool
    let modelDisplayName: String?
    /// Receives the paste handler to install on the text view.
    @ViewBuilder let field: (@escaping ([UIImage]) -> Void) -> Field
    @ViewBuilder let buttons: () -> Buttons

    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showingVisionAlert = false
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    #if canImport(UIKit)
    @State private var previewAttachment: ChatImageAttachment?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                attachmentStrip
            }

            VStack(alignment: .leading, spacing: 0) {
                field(handlePastedImages)

                HStack(alignment: .center, spacing: 2) {
                    plusMenuButton
                    buttons()
                }
                .padding(.leading, 2)
                .padding(.trailing, 4)
                .padding(.bottom, 4)
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
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
        #if canImport(UIKit)
        .fullScreenCover(item: $previewAttachment) { attachment in
            if let uiImage = UIImage(data: attachment.data) {
                ImagePreviewView(image: uiImage)
            }
        }
        #endif
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

    // MARK: - Intake

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

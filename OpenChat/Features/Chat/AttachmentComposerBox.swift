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

/// Rounded composer box that owns image and document attachments: the
/// thumbnail/chip strip, the plus menu (Camera / Photos / Paste Image /
/// Browse Files / Paste Document), drag-and-drop, and paste.
///
/// Shared by the main composer and the edit screen, which differ only in what
/// they put in the two slots — the text field, and the buttons trailing the
/// plus menu (the host supplies its own `Spacer` and send button). The edit
/// screen doesn't support documents, so it passes `.constant([])` and
/// `supportsFiles: false`.
struct AttachmentComposerBox<Field: View, Buttons: View>: View {
    @Binding var attachments: [ChatImageAttachment]
    @Binding var documentAttachments: [ChatDocumentAttachment]
    let supportsVision: Bool
    let supportsFiles: Bool
    let modelDisplayName: String?
    /// Receives the image and document paste handlers to install on the text view.
    @ViewBuilder let field: (@escaping ([UIImage]) -> Void, @escaping (Data, String?) -> Void) -> Field
    @ViewBuilder let buttons: () -> Buttons

    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showingVisionAlert = false
    @State private var showingFilesAlert = false
    @State private var showingInvalidDocumentAlert = false
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var showingFileImporter = false
    #if canImport(UIKit)
    @State private var previewAttachment: ChatImageAttachment?
    @State private var previewDocument: ChatDocumentAttachment?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty || !documentAttachments.isEmpty {
                attachmentStrip
            }

            VStack(alignment: .leading, spacing: 0) {
                field(handlePastedImages, handlePastedDocument)

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

    private var plusMenuButton: some View {
        Menu {
            if CameraCaptureAvailability.isAvailable {
                Button {
                    Haptics.light()
                    requestCamera()
                } label: {
                    Label("Camera", systemImage: "camera")
                }
            }

            Button {
                Haptics.light()
                requestPhotoLibrary()
            } label: {
                Label("Photos", systemImage: "photo")
            }

            Button {
                Haptics.light()
                pasteFromClipboard()
            } label: {
                Label("Paste Image", systemImage: "doc.on.clipboard")
            }

            Button {
                Haptics.light()
                requestFiles()
            } label: {
                Label("Browse Files", systemImage: "doc")
            }

            Button {
                Haptics.light()
                pasteDocumentFromClipboard()
            } label: {
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

    private func requestFiles() {
        guard supportsFiles else {
            Haptics.warning()
            showingFilesAlert = true
            return
        }
        showingFileImporter = true
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

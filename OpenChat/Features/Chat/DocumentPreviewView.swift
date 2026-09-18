import SwiftUI
#if canImport(UIKit)
import UIKit
import QuickLook

struct DocumentPreviewView: View {
    let attachment: ChatDocumentAttachment
    @Environment(\.dismiss) private var dismiss
    @State private var previewURL: URL?
    @State private var loadFailed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let previewURL {
                QuickLookPreview(url: previewURL).ignoresSafeArea()
            } else if loadFailed {
                ContentUnavailableView {
                    Label("Couldn't Open Document", systemImage: "doc.badge.exclamationmark")
                } description: {
                    Text("The file may be corrupted or unsupported.")
                }
                .foregroundStyle(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.28))
                    .padding(16)
            }
            .accessibilityLabel("Close preview")
        }
        .statusBarHidden(true)
        .task {
            if let url = Self.writeTempFile(for: attachment) {
                previewURL = url
            } else {
                loadFailed = true
            }
        }
        .onDisappear {
            if let previewURL {
                try? FileManager.default.removeItem(at: previewURL)
            }
        }
    }

    private static func writeTempFile(for attachment: ChatDocumentAttachment) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeFilename = (attachment.filename as NSString).lastPathComponent
            let url = directory.appendingPathComponent(safeFilename)
            try attachment.data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif

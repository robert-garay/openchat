import CoreGraphics
import Foundation

/// Ordered set of chat images the full-screen preview can page through.
///
/// Attachments are listed in chronological message order, then in the order they
/// appear on each message, so swiping left/right in the viewer matches the thread.
struct ImageGallery: Equatable {
    let attachments: [ChatImageAttachment]
    var selectedIndex: Int

    init(attachments: [ChatImageAttachment], selectedID: UUID? = nil) {
        self.attachments = attachments
        self.selectedIndex = Self.index(of: selectedID, in: attachments)
    }

    /// Images from `messages`, sorted by `createdAt` so callers don't have to pre-sort.
    static func attachments(in messages: [ChatMessage]) -> [ChatImageAttachment] {
        messages
            .sorted { $0.createdAt < $1.createdAt }
            .flatMap(\.imageAttachments)
    }

    var selectedAttachment: ChatImageAttachment? {
        attachments.indices.contains(selectedIndex) ? attachments[selectedIndex] : nil
    }

    var canGoPrevious: Bool { selectedIndex > 0 }

    var canGoNext: Bool { selectedIndex + 1 < attachments.count }

    mutating func selectPrevious() {
        guard canGoPrevious else { return }
        selectedIndex -= 1
    }

    mutating func selectNext() {
        guard canGoNext else { return }
        selectedIndex += 1
    }

    private static func index(of selectedID: UUID?, in attachments: [ChatImageAttachment]) -> Int {
        guard !attachments.isEmpty else { return 0 }
        if let selectedID, let index = attachments.firstIndex(where: { $0.id == selectedID }) {
            return index
        }
        return 0
    }
}

/// Decides whether a drag on the full-screen image preview should close it.
///
/// Only a downward, vertically dominant gesture counts, so left/right paging
/// and pinch-zoom pan are left alone. A short drag springs back; a long drag
/// or a downward flick dismisses.
enum ImagePreviewDismissPolicy {
    static let distanceThreshold: CGFloat = 140
    static let flickThreshold: CGFloat = 280
    static let minimumDownward: CGFloat = 24

    static func shouldDismiss(translation: CGSize, predictedEndTranslation: CGSize) -> Bool {
        guard translation.height >= minimumDownward else { return false }
        guard translation.height >= abs(translation.width) else { return false }
        if translation.height >= distanceThreshold { return true }
        return predictedEndTranslation.height >= flickThreshold
    }
}

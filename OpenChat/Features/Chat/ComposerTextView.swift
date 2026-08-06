import SwiftUI
#if canImport(UIKit)
import UIKit

/// UITextView subclass that intercepts paste commands for images so the composer
/// can attach them without the user leaving the text input.
///
/// Text paste keeps the default behavior. Documents are left as a TODO so the
/// same interception path can be extended once the app adds file attachments.
private final class PasteInterceptingTextView: UITextView {
    /// Called when the pasteboard contains one or more images.
    var onPasteImages: (([UIImage]) -> Void)?

    override func paste(_ sender: Any?) {
        if let images = UIPasteboard.general.images, !images.isEmpty, let onPasteImages {
            onPasteImages(images)
            return
        }

        // Future document support: inspect UIPasteboard.general.itemProviders
        // for UTType.pdf / UTType.fileURL and emit `.document(Data)` here.

        super.paste(sender)
    }
}

/// UITextView-backed composer field. SwiftUI `TextField`/`TextEditor` re-layout
/// the full string on every keystroke and become unusable for large pastes.
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Single-line floor; empty text always resolves to roughly one body line.
    var minHeight: CGFloat = 22
    /// ~5–6 body lines (similar to the old `TextField` `.lineLimit(1...6)`).
    var maxHeight: CGFloat = 120
    /// Called when the user pastes images into the composer. Text paste still
    /// uses the default UITextView behavior.
    var onPasteImages: (([UIImage]) -> Void)?
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = PasteInterceptingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = false
        textView.keyboardDismissMode = .interactive
        textView.returnKeyType = .default
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.text = text
        textView.textColor = .label
        textView.accessibilityLabel = placeholder

        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
        ])
        context.coordinator.placeholderLabel = placeholderLabel
        context.coordinator.updatePlaceholder(for: textView)

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if let pasteView = textView as? PasteInterceptingTextView {
            pasteView.onPasteImages = onPasteImages
        }
        textView.isEditable = isEnabled
        textView.textColor = isEnabled ? .label : .secondaryLabel
        if !isEnabled {
            textView.resignFirstResponder()
        }
        context.coordinator.parent = self
        if textView.text != text {
            let selected = textView.selectedRange
            textView.text = text
            // Preserve caret when possible (NSRange is UTF-16).
            let utf16Count = (textView.text as NSString).length
            if selected.location <= utf16Count {
                textView.selectedRange = selected
            }
        }
        context.coordinator.updatePlaceholder(for: textView)
        context.coordinator.recalculateHeight(for: textView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width.isFinite, width > 0 else {
            return CGSize(width: proposal.width ?? 0, height: Self.singleLineHeight(for: uiView, minHeight: minHeight))
        }
        let height = Self.clampedHeight(for: uiView, width: width, minHeight: minHeight, maxHeight: maxHeight)
        uiView.isScrollEnabled = Self.contentHeight(for: uiView, width: width) > maxHeight + 0.5
        return CGSize(width: width, height: height)
    }

    /// One body line — empty `UITextView.sizeThatFits` often reports an oversized height.
    static func singleLineHeight(for textView: UITextView, minHeight: CGFloat) -> CGFloat {
        let font = textView.font ?? .preferredFont(forTextStyle: .body)
        return max(minHeight, ceil(font.lineHeight))
    }

    static func contentHeight(for textView: UITextView, width: CGFloat) -> CGFloat {
        let text = textView.text ?? ""
        if text.isEmpty {
            return singleLineHeight(for: textView, minHeight: 0)
        }
        let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return max(fitting.height, singleLineHeight(for: textView, minHeight: 0))
    }

    static func clampedHeight(
        for textView: UITextView,
        width: CGFloat,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) -> CGFloat {
        let line = singleLineHeight(for: textView, minHeight: minHeight)
        let content = contentHeight(for: textView, width: width)
        return min(max(content, line), maxHeight)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView
        var placeholderLabel: UILabel?
        private var lastReportedHeight: CGFloat = 0

        init(_ parent: ComposerTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            updatePlaceholder(for: textView)
            recalculateHeight(for: textView)
        }

        func updatePlaceholder(for textView: UITextView) {
            placeholderLabel?.isHidden = !textView.text.isEmpty
        }

        func recalculateHeight(for textView: UITextView) {
            let width = textView.bounds.width
            guard width > 0 else { return }
            let content = ComposerTextView.contentHeight(for: textView, width: width)
            let height = ComposerTextView.clampedHeight(
                for: textView,
                width: width,
                minHeight: parent.minHeight,
                maxHeight: parent.maxHeight
            )
            textView.isScrollEnabled = content > parent.maxHeight + 0.5
            guard abs(height - lastReportedHeight) > 0.5 else { return }
            lastReportedHeight = height
            // Invalidate SwiftUI layout when the intrinsic text height changes.
            textView.invalidateIntrinsicContentSize()
        }
    }
}
#endif

import SwiftUI
#if canImport(UIKit)
import UIKit

/// UITextView-backed composer field. SwiftUI `TextField`/`TextEditor` re-layout
/// the full string on every keystroke and become unusable for large pastes.
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 24
    var maxHeight: CGFloat = 120

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
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
            return CGSize(width: proposal.width ?? 0, height: minHeight)
        }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let height = min(max(fitting.height, minHeight), maxHeight)
        uiView.isScrollEnabled = fitting.height > maxHeight + 0.5
        return CGSize(width: width, height: height)
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
            let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            let height = min(max(fitting.height, parent.minHeight), parent.maxHeight)
            textView.isScrollEnabled = fitting.height > parent.maxHeight + 0.5
            guard abs(height - lastReportedHeight) > 0.5 else { return }
            lastReportedHeight = height
            // Invalidate SwiftUI layout when the intrinsic text height changes.
            textView.invalidateIntrinsicContentSize()
        }
    }
}
#endif

import SwiftUI
#if canImport(UIKit)
import UIKit

/// Full-screen image preview with pinch / double-tap zoom and pan.
struct ImagePreviewView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            ZoomableScrollView(image: image)
                .ignoresSafeArea()

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
    }
}

/// UIScrollView-backed zoom so pinch and double-tap feel native.
private struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = LayoutAwareScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.onBoundsChange = { [weak coordinator = context.coordinator] in
            coordinator?.layoutImageIfNeeded(force: false)
        }

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.layoutImageIfNeeded(force: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(image: image)
    }

    final class LayoutAwareScrollView: UIScrollView {
        var onBoundsChange: (() -> Void)?
        private var lastBoundsSize: CGSize = .zero

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.size != lastBoundsSize else { return }
            lastBoundsSize = bounds.size
            onBoundsChange?()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let image: UIImage
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        private var configuredBoundsSize: CGSize = .zero

        init(image: UIImage) {
            self.image = image
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage()
        }

        func layoutImageIfNeeded(force: Bool) {
            guard let scrollView, let imageView else { return }
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }
            guard force || boundsSize != configuredBoundsSize else { return }
            configuredBoundsSize = boundsSize

            imageView.frame = CGRect(origin: .zero, size: image.size)
            let widthScale = boundsSize.width / max(image.size.width, 1)
            let heightScale = boundsSize.height / max(image.size.height, 1)
            let fitScale = min(widthScale, heightScale)

            scrollView.minimumZoomScale = fitScale
            scrollView.maximumZoomScale = max(fitScale * 5, fitScale + 0.01)
            scrollView.zoomScale = fitScale
            scrollView.contentSize = image.size
            centerImage()
        }

        /// Recenters by repositioning the image view's own frame rather than mutating
        /// `scrollView.contentInset`. Adjusting `contentInset` from inside `scrollViewDidZoom`
        /// fights the scroll view's own offset clamping during a live pinch+pan gesture — the
        /// inset keeps changing while the gesture is still in flight, which lets the content
        /// drift past its bounds instead of being clamped. Frame-origin centering (Apple's
        /// PhotoScroller pattern) never touches the offset-clamping metadata, so the image
        /// can't be dragged past its edges.
        func centerImage() {
            guard let scrollView, let imageView else { return }
            let boundsSize = scrollView.bounds.size
            var frame = imageView.frame

            frame.origin.x = frame.width < boundsSize.width ? (boundsSize.width - frame.width) / 2 : 0
            frame.origin.y = frame.height < boundsSize.height ? (boundsSize.height - frame.height) / 2 : 0
            imageView.frame = frame
            scrollView.contentInset = .zero
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale * 1.05 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let target = min(scrollView.minimumZoomScale * 2.5, scrollView.maximumZoomScale)
                let point = gesture.location(in: imageView)
                zoom(to: point, scale: target, in: scrollView)
            }
        }

        private func zoom(to point: CGPoint, scale: CGFloat, in scrollView: UIScrollView) {
            let size = scrollView.bounds.size
            let width = size.width / scale
            let height = size.height / scale
            let rect = CGRect(
                x: point.x - width / 2,
                y: point.y - height / 2,
                width: width,
                height: height
            )
            scrollView.zoom(to: rect, animated: true)
        }
    }
}

#endif

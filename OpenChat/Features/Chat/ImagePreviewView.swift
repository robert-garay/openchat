import SwiftUI
import UIKit

/// Full-screen image preview with pinch / double-tap zoom, pan, and paging
/// across every image in the current chat thread (or composer strip).
///
/// Pan/zoom is implemented directly with SwiftUI gestures and an explicitly
/// clamped offset, rather than a `UIScrollView` wrapper. The offset is always
/// computed and clamped by this view's own code, so it can never end up
/// outside the image's bounds no matter what sequence of gestures produced it —
/// there's no UIKit-internal scroll/zoom state to get out of sync with.
///
/// Horizontal paging is disabled while zoomed so a pan cannot accidentally
/// flip to the next image. At 1x, swipe left/right (or the chevrons) moves
/// between images, and swipe down dismisses the viewer.
struct ImagePreviewView: View {
    @State private var gallery: ImageGallery
    @State private var isZoomed = false
    @State private var dismissOffset: CGFloat = 0
    @State private var isDraggingToDismiss = false
    @Environment(\.dismiss) private var dismiss

    init(attachments: [ChatImageAttachment], initialID: UUID) {
        _gallery = State(initialValue: ImageGallery(attachments: attachments, selectedID: initialID))
    }

    private var dismissProgress: CGFloat {
        min(1.0, max(0.0, dismissOffset) / 320.0)
    }

    private var backdropOpacity: CGFloat { 1.0 - dismissProgress * 0.75 }

    private var imageScale: CGFloat { 1.0 - dismissProgress * 0.08 }

    private var chromeOpacity: CGFloat { 1.0 - dismissProgress }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()

            TabView(selection: $gallery.selectedIndex) {
                ForEach(Array(gallery.attachments.enumerated()), id: \.element.id) { index, attachment in
                    ZoomableImagePage(
                        attachment: attachment,
                        isActive: index == gallery.selectedIndex,
                        isZoomed: $isZoomed
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(isZoomed || isDraggingToDismiss)
            .offset(y: max(0, dismissOffset))
            .scaleEffect(imageScale, anchor: .top)
            .ignoresSafeArea()
            .onChange(of: gallery.selectedIndex) { _, _ in
                isZoomed = false
            }
        }
        .simultaneousGesture(dismissDrag, including: isZoomed ? .none : .all)
        .onChange(of: isZoomed) { _, zoomed in
            if zoomed {
                dismissOffset = 0
                isDraggingToDismiss = false
            }
        }
        .overlay(alignment: .topTrailing) {
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
            .opacity(chromeOpacity)
        }
        .overlay(alignment: .leading) {
            if gallery.attachments.count > 1 {
                pagingButton(
                    systemName: "chevron.left.circle.fill",
                    label: "Previous image",
                    enabled: gallery.canGoPrevious
                ) {
                    selectPrevious()
                }
                .padding(.leading, 8)
                .opacity(chromeOpacity)
            }
        }
        .overlay(alignment: .trailing) {
            if gallery.attachments.count > 1 {
                pagingButton(
                    systemName: "chevron.right.circle.fill",
                    label: "Next image",
                    enabled: gallery.canGoNext
                ) {
                    selectNext()
                }
                .padding(.trailing, 8)
                .opacity(chromeOpacity)
            }
        }
        .overlay(alignment: .bottom) {
            if gallery.attachments.count > 1 {
                Text("\(gallery.selectedIndex + 1) of \(gallery.attachments.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: Capsule())
                    .padding(.bottom, 28)
                    .accessibilityLabel("Image \(gallery.selectedIndex + 1) of \(gallery.attachments.count)")
                    .allowsHitTesting(false)
                    .opacity(chromeOpacity)
            }
        }
        .presentationBackground(.clear)
        .statusBarHidden(true)
        .accessibilityAction(named: "Previous image") { selectPrevious() }
        .accessibilityAction(named: "Next image") { selectNext() }
        .accessibilityHint(isZoomed ? "Zoomed. Double-tap to reset zoom." : "Swipe left or right for other images. Swipe down to close.")
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let dy = value.translation.height
                let dx = value.translation.width
                guard dy > abs(dx) else { return }
                isDraggingToDismiss = true
                dismissOffset = max(0, dy)
            }
            .onEnded { value in
                if ImagePreviewDismissPolicy.shouldDismiss(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                ) {
                    Haptics.light()
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        dismissOffset = 0
                        isDraggingToDismiss = false
                    }
                }
            }
    }

    private func pagingButton(
        systemName: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 32))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .white.opacity(enabled ? 0.28 : 0.12))
                .padding(12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(label)
        .accessibilityHidden(!enabled)
    }

    private func selectPrevious() {
        guard gallery.canGoPrevious else { return }
        isZoomed = false
        Haptics.light()
        withAnimation(.easeInOut(duration: 0.25)) {
            gallery.selectPrevious()
        }
    }

    private func selectNext() {
        guard gallery.canGoNext else { return }
        isZoomed = false
        Haptics.light()
        withAnimation(.easeInOut(duration: 0.25)) {
            gallery.selectNext()
        }
    }
}

/// One page in the image gallery. Owns its own pinch/pan/double-tap zoom state.
private struct ZoomableImagePage: View {
    let attachment: ChatImageAttachment
    let isActive: Bool
    @Binding var isZoomed: Bool

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        Group {
            if let image = UIImage(data: attachment.data) {
                zoomableImage(image)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Image unavailable")
            }
        }
        .onChange(of: isActive) { _, active in
            if !active {
                resetZoom()
            }
        }
    }

    private func zoomableImage(_ image: UIImage) -> some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let fittedSize = Self.fittedSize(of: image.size, in: containerSize)
            let zoomed = scale > minScale * 1.001

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: containerSize.width, height: containerSize.height)
                .scaleEffect(scale)
                .offset(offset)
                .contentShape(Rectangle())
                .gesture(magnificationGesture(fittedSize: fittedSize, containerSize: containerSize))
                .simultaneousGesture(
                    panGesture(fittedSize: fittedSize, containerSize: containerSize),
                    including: zoomed ? .all : .none
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if scale > minScale * 1.05 {
                            scale = minScale
                            offset = .zero
                        } else {
                            scale = min(minScale * 2.5, maxScale)
                            offset = Self.clampedOffset(
                                offset,
                                fittedSize: fittedSize,
                                scale: scale,
                                containerSize: containerSize
                            )
                        }
                        committedScale = scale
                        committedOffset = offset
                        publishZoomed()
                    }
                }
        }
        .ignoresSafeArea()
    }

    private func magnificationGesture(fittedSize: CGSize, containerSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = (committedScale * value).clamped(to: minScale...maxScale)
                offset = Self.clampedOffset(offset, fittedSize: fittedSize, scale: scale, containerSize: containerSize)
                publishZoomed()
            }
            .onEnded { _ in
                committedScale = scale
                committedOffset = offset
                publishZoomed()
            }
    }

    private func panGesture(fittedSize: CGSize, containerSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minScale * 1.001 else { return }
                let proposed = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
                offset = Self.clampedOffset(proposed, fittedSize: fittedSize, scale: scale, containerSize: containerSize)
            }
            .onEnded { _ in
                committedOffset = offset
            }
    }

    private func publishZoomed() {
        guard isActive else { return }
        isZoomed = scale > minScale * 1.001
    }

    private func resetZoom() {
        scale = minScale
        committedScale = minScale
        offset = .zero
        committedOffset = .zero
    }

    /// The size the image actually renders at under `.scaledToFit()` inside `containerSize`.
    private static func fittedSize(of imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return containerSize }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        if imageAspect > containerAspect {
            let width = containerSize.width
            return CGSize(width: width, height: width / imageAspect)
        } else {
            let height = containerSize.height
            return CGSize(width: height * imageAspect, height: height)
        }
    }

    /// Clamps a proposed pan offset so the image can never be dragged past its own edges:
    /// the maximum offset in each axis is exactly half of how much the scaled image
    /// overhangs the container in that axis (zero once the image is smaller than the
    /// container, e.g. a letterboxed axis at low zoom).
    private static func clampedOffset(_ proposed: CGSize, fittedSize: CGSize, scale: CGFloat, containerSize: CGSize) -> CGSize {
        let scaledWidth = fittedSize.width * scale
        let scaledHeight = fittedSize.height * scale
        let maxX = max(0, (scaledWidth - containerSize.width) / 2)
        let maxY = max(0, (scaledHeight - containerSize.height) / 2)
        return CGSize(
            width: proposed.width.clamped(to: -maxX...maxX),
            height: proposed.height.clamped(to: -maxY...maxY)
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

import SwiftUI
import UIKit

/// Full-screen image preview with pinch / double-tap zoom and pan.
///
/// Pan/zoom is implemented directly with SwiftUI gestures and an explicitly
/// clamped offset, rather than a `UIScrollView` wrapper. The offset is always
/// computed and clamped by this view's own code, so it can never end up
/// outside the image's bounds no matter what sequence of gestures produced it —
/// there's no UIKit-internal scroll/zoom state to get out of sync with.
struct ImagePreviewView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                let containerSize = proxy.size
                let fittedSize = Self.fittedSize(of: image.size, in: containerSize)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: containerSize.width, height: containerSize.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = (committedScale * value).clamped(to: minScale...maxScale)
                                    offset = Self.clampedOffset(offset, fittedSize: fittedSize, scale: scale, containerSize: containerSize)
                                }
                                .onEnded { _ in
                                    committedScale = scale
                                    committedOffset = offset
                                },
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
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if scale > minScale * 1.05 {
                                scale = minScale
                                offset = .zero
                            } else {
                                scale = min(minScale * 2.5, maxScale)
                                offset = Self.clampedOffset(offset, fittedSize: fittedSize, scale: scale, containerSize: containerSize)
                            }
                            committedScale = scale
                            committedOffset = offset
                        }
                    }
            }
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

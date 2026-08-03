import SwiftUI

/// Mini ghost mark for temporary / incognito chat (Claude-style).
struct GhostIcon: View {
    var size: CGFloat = 18
    var filled: Bool = false

    var body: some View {
        ZStack {
            GhostBody()
                .fill(filled ? AnyShapeStyle(.foreground) : AnyShapeStyle(.clear))
            GhostBody()
                .stroke(.foreground, style: StrokeStyle(lineWidth: filled ? 0 : 1.35, lineJoin: .round))

            HStack(spacing: size * 0.22) {
                Circle().frame(width: size * 0.13, height: size * 0.13)
                Circle().frame(width: size * 0.13, height: size * 0.13)
            }
            .foregroundStyle(filled ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.foreground))
            .offset(y: -size * 0.08)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct GhostBody: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let left = rect.minX + w * 0.08
        let right = rect.maxX - w * 0.08
        let top = rect.minY + h * 0.06
        let hem = rect.maxY - h * 0.08
        let bodyBottom = hem - h * 0.02
        let midX = rect.midX

        var path = Path()
        path.move(to: CGPoint(x: left, y: top + h * 0.38))
        path.addQuadCurve(
            to: CGPoint(x: right, y: top + h * 0.38),
            control: CGPoint(x: midX, y: top - h * 0.04)
        )
        path.addLine(to: CGPoint(x: right, y: bodyBottom))

        let span = right - left
        let third = span / 3
        path.addQuadCurve(
            to: CGPoint(x: right - third, y: bodyBottom),
            control: CGPoint(x: right - third * 0.5, y: hem + h * 0.08)
        )
        path.addQuadCurve(
            to: CGPoint(x: left + third, y: bodyBottom),
            control: CGPoint(x: midX, y: hem - h * 0.06)
        )
        path.addQuadCurve(
            to: CGPoint(x: left, y: bodyBottom),
            control: CGPoint(x: left + third * 0.5, y: hem + h * 0.08)
        )

        path.closeSubpath()
        return path
    }
}

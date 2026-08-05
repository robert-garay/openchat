import SwiftUI

/// Mini Pac-Man–style ghost for temporary / incognito chat.
struct GhostIcon: View {
    var size: CGFloat = 18
    var filled: Bool = false

    var body: some View {
        ZStack {
            GhostBody()
                .fill(filled ? AnyShapeStyle(.foreground) : AnyShapeStyle(.clear))
            GhostBody()
                .stroke(.foreground, style: StrokeStyle(lineWidth: filled ? 0 : 1.25, lineJoin: .round))

            HStack(spacing: size * 0.14) {
                PacManEye(size: size, filled: filled)
                PacManEye(size: size, filled: filled)
            }
            .offset(y: -size * 0.06)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct PacManEye: View {
    var size: CGFloat
    var filled: Bool

    var body: some View {
        Ellipse()
            .fill(filled ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.foreground))
            .frame(width: size * 0.22, height: size * 0.28)
            .overlay(alignment: .bottomTrailing) {
                Ellipse()
                    .fill(filled ? AnyShapeStyle(.foreground) : AnyShapeStyle(Color(.systemBackground)))
                    .frame(width: size * 0.10, height: size * 0.13)
                    .padding(.trailing, size * 0.01)
                    .padding(.bottom, size * 0.03)
            }
    }
}

/// Domed head, straight sides, three scalloped flaps — arcade ghost silhouette.
private struct GhostBody: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let flapTop = rect.maxY - h * 0.22
        let flapTip = rect.maxY - h * 0.01
        let span = right - left
        let radius = span * 0.5
        let domeCenterY = top + radius

        var path = Path()
        path.move(to: CGPoint(x: left, y: flapTop))
        path.addLine(to: CGPoint(x: left, y: domeCenterY))
        path.addArc(
            center: CGPoint(x: rect.midX, y: domeCenterY),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: right, y: flapTop))

        // Three downward scallops (Pac-Man skirt)
        let scallopW = span / 3
        for i in 0..<3 {
            let xStart = right - CGFloat(i) * scallopW
            let xMid = xStart - scallopW * 0.5
            let xEnd = xStart - scallopW
            path.addQuadCurve(
                to: CGPoint(x: xMid, y: flapTip),
                control: CGPoint(x: xStart - scallopW * 0.15, y: flapTop + h * 0.02)
            )
            path.addQuadCurve(
                to: CGPoint(x: xEnd, y: flapTop),
                control: CGPoint(x: xEnd + scallopW * 0.15, y: flapTop + h * 0.02)
            )
        }

        path.closeSubpath()
        return path
    }
}

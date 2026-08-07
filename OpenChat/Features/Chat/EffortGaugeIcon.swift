import SwiftUI

/// A compact gauge icon that adapts its tick count and needle angle to the model's
/// supported effort levels and the currently selected level.
struct EffortGaugeIcon: View {
    let level: EffortLevel
    let levels: [EffortLevel]
    var color: Color = .accentColor
    var size: CGFloat = 20

    private var levelIndex: Int { levels.firstIndex(of: level) ?? 0 }
    private var tickCount: Int { max(2, levels.count) }

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height * 0.85)
            let radius = min(canvasSize.width, canvasSize.height) * 0.46
            let lineWidth = max(1.5, size * 0.12)
            let tickWidth = max(1.5, size * 0.06)
            let needleWidth = max(2, size * 0.08)
            let pivotRadius = max(1.5, size * 0.06)

            // Top semicircular arc.
            let arcPath = Path { path in
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(0),
                    clockwise: false
                )
            }
            context.stroke(arcPath, with: .color(color), lineWidth: lineWidth)

            // Ticks along the arc.
            for index in 0..<tickCount {
                let angle = tickAngle(for: index)
                let inner = point(center: center, radius: radius * 0.75, angle: angle)
                let outer = point(center: center, radius: radius * 0.96, angle: angle)
                let tickPath = Path { path in
                    path.move(to: inner)
                    path.addLine(to: outer)
                }
                context.stroke(tickPath, with: .color(color), lineWidth: tickWidth)
            }

            // Needle pointing to the current level.
            let needleAngle = tickAngle(for: levelIndex)
            let needleInner = point(center: center, radius: radius * 0.14, angle: needleAngle)
            let needleOuter = point(center: center, radius: radius * 0.90, angle: needleAngle)
            let needlePath = Path { path in
                path.move(to: needleInner)
                path.addLine(to: needleOuter)
            }
            context.stroke(needlePath, with: .color(color), lineWidth: needleWidth)

            // Pivot cap.
            let pivot = Path(ellipseIn: CGRect(
                x: center.x - pivotRadius,
                y: center.y - pivotRadius,
                width: pivotRadius * 2,
                height: pivotRadius * 2
            ))
            context.fill(pivot, with: .color(color))
        }
        .frame(width: size, height: size)
    }

    private func tickAngle(for index: Int) -> Angle {
        let span: Double = 180
        let start: Double = 180
        guard tickCount > 1 else { return .degrees(start) }
        let step = span / Double(tickCount - 1)
        return .degrees(start + Double(index) * step)
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle.radians) * radius,
            y: center.y + sin(angle.radians) * radius
        )
    }
}

#Preview {
    HStack(spacing: 20) {
        EffortGaugeIcon(level: .none, levels: [.none, .low, .medium, .high, .xhigh, .max])
        EffortGaugeIcon(level: .low, levels: [.none, .low, .medium, .high, .xhigh, .max])
        EffortGaugeIcon(level: .medium, levels: [.low, .medium, .high])
        EffortGaugeIcon(level: .high, levels: [.low, .medium, .high, .xhigh])
        EffortGaugeIcon(level: .max, levels: [.high, .max])
    }
}

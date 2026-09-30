import SwiftUI

struct LocalModelTierBadge: View {
    let label: RecommendationPickLabel
    var compact: Bool = false

    var body: some View {
        Text(label.title)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(label.foregroundColor)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 3)
            .background(label.backgroundColor, in: Capsule())
    }
}

extension RecommendationPickLabel {
    var foregroundColor: Color {
        switch self {
        case .fast:
            return Color.green
        case .balanced:
            return Color.orange
        case .strongest:
            return Color.blue
        case .alternative:
            return Color.secondary
        }
    }

    var backgroundColor: Color {
        foregroundColor.opacity(0.14)
    }
}

import SwiftUI

/// Small pill badge marking a feature as beta, e.g. next to its label in a
/// Settings row.
struct BetaBadge: View {
    var body: some View {
        Text("Beta")
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}

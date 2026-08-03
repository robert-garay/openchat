import SwiftUI

/// Tiny capability marks shown next to a model name (e.g. eye = vision).
struct ModelCapabilitySign: View {
    let supportsVision: Bool

    var body: some View {
        if supportsVision {
            Image(systemName: "eye")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Supports images")
        }
    }
}

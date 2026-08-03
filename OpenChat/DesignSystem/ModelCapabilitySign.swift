import SwiftUI

/// Tiny SF Symbol marks for a model's capabilities.
struct ModelCapabilitySigns: View {
    let capabilities: [ModelCapability]
    var limit: Int? = nil

    private var visible: [ModelCapability] {
        let ordered = ModelCapability.sorted(capabilities)
        guard let limit, limit >= 0 else { return ordered }
        return Array(ordered.prefix(limit))
    }

    var body: some View {
        if !visible.isEmpty {
            HStack(spacing: 3) {
                ForEach(visible) { capability in
                    Image(systemName: capability.symbolName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(capability.accessibilityLabel)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Compact legend explaining the capability icons.
struct ModelCapabilityLegend: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ModelCapability.displayOrder) { capability in
                    HStack(spacing: 4) {
                        Image(systemName: capability.symbolName)
                            .font(.caption2.weight(.semibold))
                        Text(capability.legendLabel)
                            .font(.caption2)
                    }
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .accessibilityElement(children: .contain)
    }
}

/// Backwards-compatible wrapper used by older call sites.
struct ModelCapabilitySign: View {
    let supportsVision: Bool
    var capabilities: [ModelCapability] = []

    private var resolved: [ModelCapability] {
        if !capabilities.isEmpty { return capabilities }
        return supportsVision ? [.vision] : []
    }

    var body: some View {
        ModelCapabilitySigns(capabilities: resolved)
    }
}

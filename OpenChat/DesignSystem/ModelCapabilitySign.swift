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

/// Provider + capability filter chrome for the model picker.
struct ModelPickerFilterBars: View {
    let providers: [ConfiguredProvider]
    @Binding var selectedProviderIDs: Set<String>
    @Binding var selectedCapabilities: Set<ModelCapability>

    var body: some View {
        VStack(spacing: 0) {
            if !providers.isEmpty {
                ModelProviderFilterBar(
                    providers: providers,
                    selectedProviderIDs: $selectedProviderIDs
                )
            }
            ModelCapabilityLegend(selectedCapabilities: $selectedCapabilities)
        }
        .background(.bar)
    }
}

/// Horizontal provider filter row. Tapping an item toggles it as a filter.
struct ModelProviderFilterBar: View {
    let providers: [ConfiguredProvider]
    @Binding var selectedProviderIDs: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(providers) { provider in
                    let isSelected = selectedProviderIDs.contains(provider.id)
                    Button {
                        Haptics.light()
                        if isSelected {
                            selectedProviderIDs.remove(provider.id)
                        } else {
                            selectedProviderIDs.insert(provider.id)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            ProviderLogoView(
                                logoAssetName: provider.logoAssetName,
                                symbolName: provider.symbolName,
                                tint: Color(hex: provider.tint),
                                size: 14,
                                cornerRadius: 3
                            )
                            Text(provider.name)
                                .font(.caption2)
                        }
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(provider.name)
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                    .accessibilityHint(
                        isSelected
                            ? "Selected. Double tap to remove this filter."
                            : "Double tap to filter models from this provider."
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Provider filters")
    }
}

/// Compact legend explaining the capability icons. Tapping an item toggles it as a filter.
struct ModelCapabilityLegend: View {
    @Binding var selectedCapabilities: Set<ModelCapability>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ModelCapability.displayOrder) { capability in
                    let isSelected = selectedCapabilities.contains(capability)
                    Button {
                        Haptics.light()
                        if isSelected {
                            selectedCapabilities.remove(capability)
                        } else {
                            selectedCapabilities.insert(capability)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: capability.symbolName)
                                .font(.caption2.weight(.semibold))
                            Text(capability.legendLabel)
                                .font(.caption2)
                        }
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(capability.legendLabel)
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                    .accessibilityHint(
                        isSelected
                            ? "Selected. Double tap to remove this filter."
                            : "Double tap to filter models with this capability."
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capability filters")
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

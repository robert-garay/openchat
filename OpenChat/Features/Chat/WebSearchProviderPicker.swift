import SwiftUI

/// Compact popover listing registered search providers with logos.
struct WebSearchProviderPicker: View {
    let providers: [WebSearchProviderKind]
    let selectedProvider: WebSearchProviderKind?
    let onSelect: (WebSearchProviderKind) -> Void
    let onDisable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Web Search")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            pickerRow(
                title: "Off",
                isSelected: selectedProvider == nil,
                action: onDisable
            ) {
                Image(systemName: "globe")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            if !providers.isEmpty {
                Divider()
                    .padding(.leading, 56)
            }

            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                pickerRow(
                    title: provider.displayName,
                    isSelected: selectedProvider == provider,
                    action: { onSelect(provider) }
                ) {
                    ProviderLogoView(
                        logoAssetName: provider.logoAssetName,
                        symbolName: provider.symbolName,
                        tint: Color(hex: provider.tintHex),
                        size: 28,
                        cornerRadius: 7
                    )
                }

                if index < providers.count - 1 {
                    Divider()
                        .padding(.leading, 56)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(minWidth: 220)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pickerRow<Icon: View>(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon()
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

import SwiftUI

/// One tile in the custom-endpoint brand mark picker: a logo (or the fallback
/// server icon) with a name caption and a selection ring.
struct CustomEndpointLogoButton: View {
    var logoAssetName: String?
    var symbolName: String
    var name: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ProviderLogoView(
                    logoAssetName: logoAssetName,
                    symbolName: symbolName,
                    tint: Color(.secondaryLabel),
                    size: 40,
                    cornerRadius: 10
                )
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                }

                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 68)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

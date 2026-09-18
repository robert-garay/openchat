import SwiftUI

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.subheadline.weight(.semibold))
            Text("No connection — waiting to retry")
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, Theme.contentPadding)
        .padding(.vertical, 10)
        .background(Color(.systemGray5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No connection. Waiting to retry.")
    }
}

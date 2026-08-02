import SwiftUI

/// Brand mark that automatically picks the light or dark asset.
struct OpenChatLogoView: View {
    var size: CGFloat = 96

    var body: some View {
        Image("OpenChatLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("OpenChat")
    }
}

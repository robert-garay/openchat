import SwiftUI

/// Two-line burger mark for the chat-list leading toolbar (ChatGPT/Grok style).
struct HamburgerIcon: View {
    var size: CGFloat = 18
    var lineWidth: CGFloat = 1.8

    var body: some View {
        VStack(spacing: size * 0.28) {
            Capsule(style: .continuous)
                .frame(width: size, height: lineWidth)
            Capsule(style: .continuous)
                .frame(width: size, height: lineWidth)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

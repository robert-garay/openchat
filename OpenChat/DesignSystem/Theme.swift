import SwiftUI

/// Shared visual language for OpenChat: soft, rounded, generous whitespace,
/// and system materials so the app always feels at home on iOS.
enum Theme {
    static let bubbleCornerRadius: CGFloat = 20
    static let smallCornerRadius: CGFloat = 12
    static let contentPadding: CGFloat = 16

    static let userBubble = Color.accentColor

    static let springFast = Animation.spring(response: 0.32, dampingFraction: 0.86)
}

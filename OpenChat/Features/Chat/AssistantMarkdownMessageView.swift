import SwiftStreamingMarkdown
import SwiftUI

/// Renders assistant message content with streaming-aware Markdown.
///
/// SwiftStreamingMarkdown parses the source asynchronously and animates newly
/// appended text so the bubble grows smoothly as tokens arrive.
struct AssistantMarkdownMessageView: View {
    let content: String

    var body: some View {
        MarkdownView(
            text: content,
            config: Self.markdownConfig
        )
    }

    private static let markdownConfig = MarkdownRenderConfig.default
        .withShouldAnimateText(value: true)
}

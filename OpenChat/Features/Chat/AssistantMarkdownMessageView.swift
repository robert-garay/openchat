import SwiftStreamingMarkdown
import SwiftUI

/// Renders assistant message content with streaming-aware Markdown.
///
/// While `message.isStreaming` is true, content is rendered via
/// `StreamedMarkdownView`, which incrementally re-parses growing snapshots
/// instead of restarting the parse on every mutation. Once streaming ends,
/// rendering swaps to the static `MarkdownView` path.
struct AssistantMarkdownMessageView: View {
    let message: ChatMessage
    let displayContent: @Sendable (ChatMessage) -> String

    @State private var source: ChatMessageMarkdownSource

    /// - Parameter displayContent: Post-processes `message.content` for display
    ///   (e.g. stripping action fences, image placeholders). Defaults to raw content.
    init(message: ChatMessage, displayContent: @escaping @Sendable (ChatMessage) -> String = \.content) {
        self.message = message
        self.displayContent = displayContent
        _source = State(wrappedValue: ChatMessageMarkdownSource(message: message, snapshot: displayContent))
    }

    var body: some View {
        if message.isStreaming {
            StreamedMarkdownView(
                source: source,
                config: Self.markdownConfig
            )
        } else {
            MarkdownView(
                text: displayContent(message),
                config: Self.markdownConfig
            )
        }
    }

    static let markdownConfig = MarkdownRenderConfig.default
        .withShouldAnimateText(value: true)
        .withImageConfig(
            ImageConfig(
                enabled: true,
                allowedImageTypes: [.remote(allowedDomains: [])],
                fullscreenViewerEnabled: true
            )
        )
}

/// Renders a complete (non-streaming) Markdown string, e.g. error messages.
struct StaticMarkdownMessageView: View {
    let content: String

    var body: some View {
        MarkdownView(
            text: content,
            config: AssistantMarkdownMessageView.markdownConfig
        )
    }
}

import Foundation
import SwiftStreamingMarkdown

/// Bridges a streaming `ChatMessage.content` into `StreamedMarkdownView`.
///
/// Observes `content`/`isStreaming` via the Observation framework (SwiftData
/// `@Model` properties are natively observable) and yields each growing
/// snapshot into the async stream `StreamedMarkdownView` re-parses from.
@MainActor
final class ChatMessageMarkdownSource: StreamedMarkdownSource {
    let text: AsyncStream<String>

    private let continuation: AsyncStream<String>.Continuation

    /// - Parameter snapshot: Computes the displayed string from the message's current
    ///   state. Defaults to raw `content`; callers that post-process content (stripping
    ///   action fences, image placeholders, etc.) pass their own transform so the
    ///   streamed output matches what the static render path would show.
    init(message: ChatMessage, snapshot: @escaping @Sendable (ChatMessage) -> String = \.content) {
        var continuation: AsyncStream<String>.Continuation!
        self.text = AsyncStream { continuation = $0 }
        self.continuation = continuation

        continuation.yield(snapshot(message))
        if message.isStreaming {
            Self.trackChanges(on: message, snapshot: snapshot, continuation: continuation)
        } else {
            continuation.finish()
        }
    }

    private static func trackChanges(
        on message: ChatMessage,
        snapshot: @escaping @Sendable (ChatMessage) -> String,
        continuation: AsyncStream<String>.Continuation
    ) {
        // `withObservationTracking`'s `onChange` fires during `willSet` — the mutated
        // property hasn't actually been stored yet at the point this callback runs.
        // Reading `snapshot(message)` synchronously here would capture the *old* value,
        // so the read is deferred to the next main-actor turn (after the mutation lands)
        // via `Task`. `onChange` is `@Sendable`, but `content`/`isStreaming` are only ever
        // mutated from `@MainActor`-isolated call sites (ChatViewModel,
        // BackgroundGenerationService), so it's safe to smuggle the non-Sendable
        // `ChatMessage` across via an unchecked box.
        let box = UncheckedSendableBox(value: message)
        withObservationTracking {
            _ = message.content
            _ = message.isStreaming
            _ = message.attachmentsData
        } onChange: {
            Task { @MainActor in
                let message = box.value
                continuation.yield(snapshot(message))
                if message.isStreaming {
                    trackChanges(on: message, snapshot: snapshot, continuation: continuation)
                } else {
                    continuation.finish()
                }
            }
        }
    }
}

/// Wraps a non-Sendable value for a single, known-safe crossing of a `@Sendable`
/// closure boundary. Callers are responsible for the actual isolation guarantee.
private struct UncheckedSendableBox<Wrapped>: @unchecked Sendable {
    let value: Wrapped
}

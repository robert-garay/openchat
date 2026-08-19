# Markdown Rendering Standardization & Streaming Fix — Design

## Summary

Fix the broken real-time streaming markdown rendering (assistant replies
currently render "all at once" instead of growing smoothly token by token),
standardize the app's two markdown rendering call sites on one config, enable
inline markdown image rendering, and strip stray markdown syntax out of
plain-text UI surfaces (chat titles) that must never show raw `**`/`*`/`` ` ``
characters.

## Background

`AssistantMarkdownMessageView.swift` renders assistant message content using
`SwiftStreamingMarkdown`'s static `MarkdownView(text:)` entry point. That API
drives its parse via SwiftUI's `.task(id: text)` modifier, which **cancels
and restarts the entire parse from scratch on every `text` mutation**.
`BackgroundGenerationService.runStream` flushes new tokens into
`assistantMessage.content` every 80ms while streaming, so in practice the
parse is constantly cancelled and restarted rather than incrementally
extended — the visible symptom is content appearing to "snap in" instead of
streaming smoothly.

The network layer (`OpenAICompatibleClient.streamReply`, SSE token-by-token)
and the buffering layer (`BackgroundGenerationService.runStream`, 80ms
throttled flush into `ChatMessage.content`) are both already correct and are
not touched by this change.

`SwiftStreamingMarkdown` ships a purpose-built streaming entry point,
`StreamedMarkdownView(source:)`, driven by a `StreamedMarkdownSource`
protocol (`var text: AsyncStream<String> { get }`) whose emissions are
progressively larger full-snapshot strings. Internally it runs a single
long-lived `.task { }` that survives across emissions and incrementally
re-parses, instead of restarting — this is the library's documented
recommendation for chat-style UIs.

Separately, `ConversationTitleGenerator.sanitize(_:)` strips quotes, trailing
punctuation, and `"Title:"`-style prefixes from LLM-generated titles, but
does not strip markdown syntax. A model reply like `**Trip Planning**`
passes the asterisks straight through into `Conversation.title`, which
`ChatHistoryDrawerView` renders as plain `Text` — so raw markdown characters
show up literally in the chat history sidebar.

`MarkdownRenderConfig.imageConfig` defaults to `.disabled`. The app already
handles model-generated images out-of-band via `GeneratedImageParser` →
`ChatMessage.imageAttachments` → the attachment gallery, entirely separate
from markdown `![]()` syntax, so this is additive, not a replacement.

## Scope

- Fix the streaming render path in `AssistantMarkdownMessageView`.
- Enable inline `![]()` image rendering via `ImageConfig`.
- Strip markdown syntax from generated conversation titles.
- Add unit tests for the new streaming-source adapter and the title sanitizer
  change.

### Out of scope

- `errorMessage` rendering path — arrives as a complete string, not
  streamed; stays on the static `MarkdownView` path (already correct for
  that use case).
- Document attachment UI (`documentChipRow`/`ChatDocumentAttachment`) —
  unrelated to markdown text rendering, untouched.
- `BackgroundGenerationService`'s 80ms flush cadence — not the source of the
  bug, not changed.
- Any new theming pass beyond what's needed for image rendering — the
  existing `MarkdownRenderConfig` styling already matches `Theme.swift` and
  is not being redesigned here.

## Architecture

1. **`ChatMessageMarkdownSource`** (new file,
   `OpenChat/Features/Chat/ChatMessageMarkdownSource.swift`) — a `@MainActor`
   final class conforming to `StreamedMarkdownSource`. Constructed with a
   `ChatMessage`. Uses `withObservationTracking(_:onChange:)` (SwiftData
   `@Model` properties are natively Observable) to watch `message.content`:
   on each change it yields the latest full `content` string into an
   `AsyncStream<String>`; when `message.isStreaming` is `false` it yields the
   final value and finishes the stream. The `onChange` closure captures
   `self` weakly and re-registers itself each firing — when the owning
   `@State` is deallocated (see below), the closure's next firing is a no-op
   and tracking stops on its own. No polling, no timers.

2. **`AssistantMarkdownMessageView`** (changed) — now takes `message:
   ChatMessage` instead of `content: String`. Body branches once per
   evaluation on `message.isStreaming`:
   - `true` → `StreamedMarkdownView(source: source, config: Self.markdownConfig)`,
     where `source` is a `@State private var source: ChatMessageMarkdownSource`
     created once for this message (initialized in `init` via
     `_source = State(wrappedValue: ChatMessageMarkdownSource(message: message))`).
   - `false` → the existing static `MarkdownView(text: message.content,
     config: Self.markdownConfig)`.
   When streaming ends, SwiftUI re-evaluates the branch and swaps to the
   static path (one final cheap re-parse of the finished text); the
   streaming branch's `@State` and its observation closure are deallocated,
   so no explicit teardown is needed.

3. **`MessageBubbleView`** call site updates to pass `message:` for the
   primary content view; the separate `errorMessage` call site keeps calling
   the static `MarkdownView` path directly (or a small `StaticMarkdownMessageView(content:)`
   wrapper sharing the same `markdownConfig`, to avoid duplicating the config
   constant).

4. **`Self.markdownConfig`** (shared static, both paths) gains inline image
   support:
   ```swift
   .withImageConfig(
       ImageConfig(
           enabled: true,
           allowedImageTypes: [.remote(allowedDomains: [])],
           fullscreenViewerEnabled: true
       )
   )
   ```
   Empty `allowedDomains` permits any `https` host per the library's
   documented behavior; `http` sources are never permitted by the library
   regardless. This does not interact with `GeneratedImageParser` — that
   pipeline strips its own placeholders before content reaches this view, so
   there's no double-rendering.

5. **`ConversationTitleGenerator.sanitize(_:)`** (changed) — after existing
   quote/punctuation/prefix stripping, additionally strip markdown emphasis
   and structural characters (`*`, `_`, `` ` ``, `#`) that survive to the
   final trimmed string, so `**Trip Planning**` → `Trip Planning`. Applied
   as a character-class trim/replace pass, not a markdown parse — titles are
   short (≤60 chars, one line) and never intentionally contain these
   characters as content.

## Error Handling

- `ChatMessageMarkdownSource`'s `AsyncStream` never throws; if `message` is
  deallocated before the stream finishes (shouldn't happen — the view holds
  it), the weak-self check in `onChange` simply stops re-registering and the
  stream is left un-finished but unobserved, which `AsyncStream` tolerates
  (no crash, garbage collected normally).
- No new error states are introduced in the render path itself;
  `SwiftStreamingMarkdown`'s own parser already degrades gracefully on
  malformed/incomplete markdown mid-stream (this is existing, trusted
  third-party behavior, not something this change alters).

## Testing

New `OpenChatTests/ChatMessageMarkdownSourceTests.swift` (Swift Testing):
- Initial `text` stream yields the message's starting content immediately.
- Mutating `message.content` while `isStreaming == true` yields each new
  snapshot in order.
- Setting `isStreaming = false` yields the final content once, then the
  stream finishes (verified by iterating to completion under a timeout).

New/updated `OpenChatTests/ConversationTitleGeneratorTests.swift`:
- `sanitize("**Trip Planning**")` → `"Trip Planning"`.
- `sanitize("# Weekend Getaway")` → `"Weekend Getaway"`.
- `sanitize("`inline code` title")` → `"inline code title"`.
- Existing quote/punctuation/prefix-stripping behavior unchanged (regression
  coverage for the existing cases already implied by current usage).

No UI/snapshot tests, per explicit scope decision — `SwiftStreamingMarkdown`
itself is treated as a trusted third-party dependency.

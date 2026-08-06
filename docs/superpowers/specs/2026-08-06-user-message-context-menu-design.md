# User Message Long-Press Context Menu — Design

## Summary

Replace the always-visible pencil `EditChip` under user message bubbles
with a long-press context menu on the user bubble itself, offering Copy,
Edit, and Select — matching ChatGPT's UX and this app's existing
long-press pattern for images.

## Background

`MessageBubbleView.swift` is the single shared view for `.user` and
`.assistant` messages. Today, `userBubble` renders the attachment
gallery, then (if not editing) `MarkdownMessageView`, followed by a
static `EditChip` (pencil icon) whenever `canEdit` is true. `canEdit` is
set globally by the caller (`ChatView.swift`) as `!viewModel.isStreaming`
— not scoped to a specific message.

The assistant side already establishes two relevant precedents in the
same file:

- A static icon-chip row (`CopyChip`, `SelectChip`) for text actions,
  gated on `!displayContent.isEmpty`.
- A `.contextMenu` long-press pattern on every rendered image
  (`attachmentGallery`), offering Copy / Share / Save to Photos.

There is no existing long-press context menu on *text* anywhere in the
app yet — only on images.

## Scope

- Remove `EditChip` (struct and call site) entirely. User bubbles show no
  static chip row.
- Add a `.contextMenu` to the text content in `userBubble`, shown only
  when `!message.content.isEmpty`, offering:
  - **Copy** (`doc.on.doc`) — `UIPasteboard.general.string = message.content`
  - **Edit** (`pencil`) — same action the old `EditChip` performed
    (`draftText = message.content; onBeginEdit?()`), shown only when
    `canEdit` is true (hidden while streaming, not merely disabled).
  - **Select** (`text.cursor`) — sets `showingTextSelection = true`,
    presenting `TextSelectionSheet(text: message.content)` via the
    existing sheet modifier.
- Add a fourth item, **Edit**, to the existing per-image `.contextMenu`
  in `attachmentGallery`, gated to `message.role == .user &&
  message.content.isEmpty` (i.e., image-only user messages, which have
  no text bubble to carry the new menu). Not shown for assistant images.
  Gated on `canEdit` the same way.

### Out of scope

- No changes to `canEdit`/`onBeginEdit`/`onSaveEdit`/`onCancelEdit`
  wiring in `ChatView.swift` — edit eligibility stays a global
  (`!isStreaming`), not per-message, gate.
- No changes to the assistant side (`CopyChip`, `SelectChip`,
  `RegenerateChip`) — those stay as-is.
- No new custom popup UI — this reuses SwiftUI's native `.contextMenu`,
  consistent with the existing image long-press pattern, not a bespoke
  floating action bar.
- No changes to `displayContent` (assistant-only calendar/memory fence
  stripping) — the new user-side menu uses `message.content` directly,
  since user messages have no such fences.

## Architecture

Two independent context menus, gated by content shape, mirroring how the
bubble already branches on text vs. image content:

```swift
#if canImport(UIKit)
if !message.content.isEmpty {
    MarkdownMessageView(...)
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
                Haptics.light()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if canEdit {
                Button {
                    draftText = message.content
                    onBeginEdit?()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }

            Button {
                Haptics.light()
                showingTextSelection = true
            } label: {
                Label("Select", systemImage: "text.cursor")
            }
        }
} else {
    MarkdownMessageView(...)
}
#endif
```

`showingTextSelection`'s `.sheet` currently hard-codes
`TextSelectionSheet(text: displayContent)` (assistant-specific). This
needs to present the correct text per caller; the simplest change is
tracking the text alongside the presentation flag rather than reusing
`displayContent`, e.g. widening the existing sheet's content to read
from a `@State private var selectionText: String` set at each call site
(`selectionText = message.content` here, `selectionText = displayContent`
on the assistant side), instead of the sheet computing `displayContent`
itself.

Image menu addition in `attachmentGallery`:

```swift
if message.role == .user && message.content.isEmpty && canEdit {
    Button {
        draftText = message.content
        onBeginEdit?()
    } label: {
        Label("Edit", systemImage: "pencil")
    }
}
```

## Error Handling

No new failure modes. `UIPasteboard` assignment and presenting a sheet
cannot fail in a user-visible way. The only new invariants are the
`canEdit` / `role == .user && content.isEmpty` guards controlling whether
Edit renders — both are simple, already-proven conditions reused from
existing code paths.

## Testing

No existing unit test coverage for `MessageBubbleView` (consistent with
prior specs in this codebase); verification is manual in the simulator:

- Long-press a user text bubble (not streaming): menu shows Copy, Edit,
  Select; each works (paste into Notes, edit flow opens prefilled,
  selection sheet shows the same text).
- Long-press a user text bubble while a response is streaming: Copy and
  Select appear, Edit does not.
- Long-press an image-only user message: existing Copy/Share/Save to
  Photos menu now also shows Edit (hidden while streaming); tapping it
  opens the edit flow.
- Pencil chip no longer renders anywhere under user messages.
- Assistant messages unaffected — no Edit ever appears on assistant text
  or images.
- Mixed text+image user message: long-pressing text shows Copy/Edit/
  Select; long-pressing the image shows Copy/Share/Save (no Edit).

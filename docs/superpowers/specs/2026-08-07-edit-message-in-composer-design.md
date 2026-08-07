# Edit Message in Full-Screen Composer — Design

## Summary

Replace inline bubble editing with a dedicated full-screen edit screen —
an X-close header titled "Edit message", the rest of the conversation
hidden, and a composer-styled box holding the message's text and image
attachments. Matches ChatGPT's edit UX.

## Background

Today, tapping Edit in the user bubble's context menu flips
`ChatViewModel.editingMessageID`, and `MessageBubbleView.userBubble`
swaps its text for an inline `TextField` (`editingBubble`) with
Cancel / Save·Send buttons. While that is active,
`ChatComposerHost` disables the main composer entirely.

The inline editor cannot change image attachments, is cramped inside the
bubble, and diverges from how every comparable app handles message
editing.

## Scope

- New full-screen edit screen presented over the chat; conversation and
  main composer are hidden while it is up.
- Text and image attachments both load into the edit screen; both can be
  changed and are saved together.
- Full image picker parity with the main composer: Camera, Photos, Paste
  Image, drag-and-drop, remove, tap-to-preview.
- Keyboard is up with the caret at the end of the text on appear.
- X dismisses without changing anything. Send applies the edit, truncates
  trailing messages, and regenerates — the existing `saveEdit` behavior.

### Out of scope

- Slash-command / skill resolution on edited text. `send()` runs
  `SkillResolver.resolve`; `saveEdit` never has and will not start.
  Editing a message to add `/some-skill` stores it as literal text.
- Voice input. No mic feature exists anywhere in OpenChat.
- Changes to the main composer's own layout or behavior.

## Architecture

1. Tap **Edit** (text context menu or image menu) → `onBeginEdit` calls
   `viewModel.beginEditing(message)` as it does today.
2. `ChatView` presents `EditMessageView` in a `.fullScreenCover(item:)`
   driven by the message matching `viewModel.editingMessageID`, seeded
   with that message's content and attachments.
3. **X** calls `viewModel.cancelEditing()` and dismisses. Nothing else
   changes.
4. **Send** calls `viewModel.saveEdit(message, newText:attachments:)`;
   the view dismisses only when that returns `true`.

`ChatComposerHost`'s `.disabled(viewModel.editingMessageID != nil)`
stays. It is moot while a full-screen cover is up, but harmless and
keeps the invariant explicit.

## Components

### `AttachmentPickerBar.swift` (new)

Extracted verbatim in behavior from `MessageComposerView`. Owns the
plus-menu button (Camera / Photos / Paste Image), `.photosPicker`,
camera `.fullScreenCover`, `.onDrop`, paste handling, the "Images not
supported" alert, and the thumbnail strip with remove buttons and
tap-to-preview.

Interface:

```swift
@Binding var attachments: [ChatImageAttachment]
let supportsVision: Bool
let modelDisplayName: String?
```

The strip and the plus button are separate views on the same type
(`strip`, `plusButton`) so each host lays them out its own way: the
strip above the text field, the plus button in the button row. The
modifiers (`photosPicker`, `onDrop`, alerts, camera cover) attach via a
single `attachmentHandlers()` view modifier the host applies to its
container.

### `EditMessageView.swift` (new)

```swift
let message: ChatMessage
let supportsVision: Bool
let modelDisplayName: String?
let onCancel: () -> Void
let onSave: (String, [ChatImageAttachment]) -> Bool
```

`@State` seeded from `message.content` and `message.imageAttachments`.

Layout: circular X button top-leading with centered "Edit message"
title, `Spacer`, then the composer box — attachment strip when
non-empty, `ComposerTextView` (autofocused), then plus button /
`Spacer` / send arrow — using the same
`Color(.secondarySystemBackground)` and `cornerRadius: 22` as the main
composer. Send is disabled when the text is blank and no attachments
remain.

### `MessageBubbleView.swift` (modified)

Delete `editingBubble`, the `isEditing` branch in `userBubble`, and the
`isEditing`, `draftText`, `onCancelEdit`, `onSaveEdit` members. The Edit
context-menu items keep calling `onBeginEdit?()`.

### `ChatView.swift` (modified)

Add the `.fullScreenCover(item:)` presenting `EditMessageView`; drop the
bubble parameters that no longer exist.

### `ChatViewModel.swift` (modified)

- `editingMessage: ChatMessage?` computed from `editingMessageID` so the
  cover can bind to an `Identifiable` item.
- `saveEdit(_:newText:)` → `@discardableResult saveEdit(_:newText:attachments:) -> Bool`,
  assigning `message.imageAttachments = attachments` alongside
  `message.content = trimmed`, with the empty-guard checking the new
  attachments rather than the message's existing ones.

### `ComposerTextView.swift` (modified)

Add `var autoFocus: Bool = false`. When true, `makeUIView` calls
`becomeFirstResponder()` and places the caret at the end of the text.
Default `false` keeps the main composer identical.

## Error Handling

**Vision guard on save.** `saveEdit` mirrors `send()`: non-empty
attachments on a model without vision sets `capabilityWarning` and
returns `false` without mutating. `AttachmentPickerBar` already blocks
adding images on such a model; this covers a model switched mid-edit.

**Silent guard failures.** `saveEdit`'s existing guards (`currentProvider`,
`currentModel`, API key present) return `false`, and `EditMessageView`
dismisses only on `true` — a misconfigured provider leaves the user in
the edit screen with their text intact instead of swallowing the edit.
No new user-facing message for that case; it matches the main
composer's current behavior.

**Cancel resets state.** X calls `cancelEditing()` before dismissing, so
`editingMessageID` clears. `.fullScreenCover` has no interactive
swipe-dismiss, so X is the only exit — no dismiss path can skip the
reset.

**Empty edit.** Send is disabled when the text is blank and attachments
are empty, so a message cannot be emptied into deletion.

**Streaming.** `canEdit: !viewModel.isStreaming` gates the menu, and
nothing can start a stream while the cover is up. `saveEdit`'s
`!isStreaming` guard becomes unreachable but stays.

## Testing

Views are not unit-tested in this codebase; logic is. Tests use XCTest,
matching the existing suite.

New tests in `OpenChatTests`:

- Assigning `imageAttachments` on a message with existing attachments
  replaces them.
- Assigning `[]` clears `attachmentsData` to `nil`.

`ConversationEditMessageTests` already covers trailing-message
truncation and needs no changes.

Manual simulator verification:

- Long-press → Edit opens the full-screen editor, keyboard up, caret at
  end.
- X returns to the chat with the message unchanged.
- Editing text and sending truncates trailing messages and regenerates.
- An image-only message opens with its thumbnail in the strip; removing
  it and sending persists the removal.
- The plus menu adds a photo mid-edit and it persists on save.
- Send is disabled when the text is cleared and no images remain.
- A non-vision model still shows the "Images not supported" alert.

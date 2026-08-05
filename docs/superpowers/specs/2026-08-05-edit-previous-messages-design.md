# Edit Previous Messages — Design

## Summary

Let the user edit the text of any of their own previous messages in a
conversation. Saving an edit updates that message's content, permanently
deletes every message that came after it (both user and assistant turns),
and triggers a fresh assistant reply — the same destructive
truncate-and-resend behavior the existing `regenerateLastReply()` already
uses for the trailing assistant message, just generalized to any point in
the history.

No branching, no version history: once an edit is saved, the old text and
the old replies are gone. This is a deliberate scope cut (see
"Out of scope").

## Background

OpenChat (`OpenChat.xcodeproj`) is a native Swift/SwiftUI iOS app. Chat
history is a flat SwiftData array: `Conversation.messages: [ChatMessage]`,
ordered via the computed `sortedMessages` (sort by `createdAt`). There is
no tree/branch structure today.

`ChatViewModel.regenerateLastReply()` already establishes the precedent
for this feature: it deletes the trailing assistant message from
`modelContext` and from `conversation.messages`, then calls
`requestAssistantReply()` to stream a new one. `MessageBubbleView` already
has a small icon-chip pattern (`CopyChip`, `RegenerateChip`) rendered
under assistant messages. This feature extends both of those existing
patterns rather than introducing new ones.

## Scope

- Editable: user messages only. Assistant messages keep their existing
  Retry/Regenerate chip; no new edit affordance is added to them.
- No branching or version history. Editing is destructive: everything
  after the edited message is deleted when the edit is saved.
- No "undo" after saving. Cancel (before saving) simply discards the
  in-progress edit and leaves everything untouched.

### Out of scope

- ChatGPT-style sibling branches with `‹ 2/3 ›` navigation between
  versions. Explicitly rejected in favor of the simpler destructive
  model — can be revisited as a separate, larger feature later if wanted.
- Editing assistant message content.
- Undo/redo of a saved edit.

## Architecture

No new persistence model. This reuses the existing flat
`Conversation.messages` SwiftData relationship and `ChatMessage` model
as-is — no schema changes.

**New pure helper on `Conversation`** (testable without a `ModelContext`,
following the pattern of existing methods like `hasUserMessages`):

```swift
/// Messages strictly after `message` in conversation order.
/// Empty if `message` is the last message or isn't found.
func messages(after message: ChatMessage) -> [ChatMessage]
```

Implemented via `sortedMessages`, finding `message`'s index and returning
the suffix after it.

**New state + methods on `ChatViewModel`:**

```swift
var editingMessageID: UUID?

func beginEditing(_ message: ChatMessage)   // guards !isStreaming, role == .user
func cancelEditing()                        // editingMessageID = nil
func saveEdit(_ message: ChatMessage, newText: String)
```

`saveEdit`:
1. Guards: `editingMessageID == message.id`, `!isStreaming`, trimmed
   `newText` is non-empty or the message has image attachments.
2. Sets `message.content = trimmed`.
3. Computes `conversation.messages(after: message)`, deletes each from
   `modelContext`, and removes them from `conversation.messages`.
4. Sets `conversation.updatedAt = .now`.
5. Sets `editingMessageID = nil`.
6. Calls the existing private `requestAssistantReply()` — the same call
   `send()` makes — to stream a new assistant reply.

Only one message can be in edit state at a time (`editingMessageID` is
singular, matching `Conversation`'s single-active-edit assumption). If the
user taps Edit on a different message while another edit is open, the
first one's unsaved draft is simply discarded (it never left local view
state — see below).

## UI / Interaction

**Trigger:** A pencil "Edit" chip appears under each user message,
styled and positioned like the existing `CopyChip`/`RegenerateChip` icon
chips (small SF Symbol, `.caption` font, `.secondary` foreground,
`.plain` button style). Hidden whenever `viewModel.isStreaming` is true,
so you can't edit mid-response.

**Editing state:** Tapping the chip swaps that bubble's content for an
inline multi-line text field, pre-filled with `message.content`, held in
local `@State private var draftText` inside `MessageBubbleView` (not
written back to the model until Save). Below the field: `Cancel` and
`Save · Send` buttons, styled like the existing calendar/memory
confirmation cards' button pairs (`.bordered` / `.borderedProminent`).

- `Cancel` → `viewModel.cancelEditing()`. `draftText` is discarded.
- `Save · Send` → `viewModel.saveEdit(message, newText: draftText)`.
  Disabled when `draftText` is empty and the message has no image
  attachments (mirrors `MessageComposerView`'s existing `canSend` logic).

**Bottom composer:** Disabled (`.disabled(...)`) while
`viewModel.editingMessageID != nil`, so there's no way to trigger a
concurrent conflicting send while an edit is in progress.

**Wiring:** `ChatMessageListView` (in `ChatView.swift`) passes
`isEditing: viewModel.editingMessageID == message.id`,
`canEdit: !viewModel.isStreaming`, and the three closures down to each
`MessageBubbleView`, same pattern already used for the calendar/memory
confirmation closures.

## Error Handling

- Empty edit with no attachments: `Save · Send` is disabled client-side;
  no round trip is attempted.
- Streaming in progress: edit chip is hidden, so `beginEditing` can't be
  triggered; `saveEdit` also guards `!isStreaming` defensively.
- Message not found in `conversation.messages` (shouldn't happen, but
  `messages(after:)` returns `[]` safely if the message isn't in the
  array, so `saveEdit` becomes a no-op truncation with just the content
  update).

## Testing

- New unit tests for `Conversation.messages(after:)` (pure, no
  `ModelContext` needed — same style as `ConversationTemporaryChatTests`):
  message is last (empty result), message in the middle (returns the
  correct suffix), message not present, multiple user/assistant pairs.
- Manual verification in the simulator: edit an early user message in a
  multi-turn conversation and confirm later messages disappear and a new
  reply streams in; confirm Cancel leaves the original message and
  history untouched; confirm the edit chip is absent while streaming.
- `ChatViewModel` itself has no existing unit test coverage (same as
  `regenerateLastReply()` today) since it depends on network streaming;
  this feature follows that existing precedent rather than introducing
  new test infrastructure for it.

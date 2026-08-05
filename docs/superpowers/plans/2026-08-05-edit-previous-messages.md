# Edit Previous Messages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user edit the text of a previous user message inline in its bubble; saving deletes every message after it and streams a fresh assistant reply — the same destructive pattern `regenerateLastReply()` already uses, generalized to any point in the history.

**Architecture:** No new persistence model. Add a pure `Conversation.messages(after:)` helper (testable without `ModelContext`) that returns the trailing suffix of `sortedMessages`. Add `editingMessageID`/`beginEditing`/`cancelEditing`/`saveEdit` to `ChatViewModel`, mirroring `regenerateLastReply()`'s delete-from-`modelContext`-and-array-then-`requestAssistantReply()` shape. Add an `EditChip` + inline `TextField` editing UI to `MessageBubbleView`'s `userBubble`, styled like the existing `CopyChip`/`RegenerateChip` and calendar/memory confirmation cards. Wire new params/closures through `ChatMessageListView` and disable the composer via `ChatComposerHost` while an edit is in progress.

**Tech Stack:** Swift, SwiftUI, SwiftData (`@Model`), Observation (`@Observable`/`@MainActor`), XCTest.

## Global Constraints

- iOS 17.0 deployment target (from `project.yml`) — `TextField(_:text:axis:)` is available.
- Test framework: this codebase's existing test target (`OpenChatTests`) uses `XCTest`/`XCTestCase` throughout (see `ConversationTemporaryChatTests.swift`), not Swift Testing. Follow that established pattern for consistency — do not introduce a second test framework into this target.
- No schema changes to `ChatMessage` or `Conversation`.
- Assistant messages are never editable by this feature — only `role == .user` messages.
- No branching, no version history, no undo after save (see `docs/superpowers/specs/2026-08-05-edit-previous-messages-design.md`).
- Run tests with `./scripts/ci-test.sh` (regenerates the Xcode project via `xcodegen` if available, then runs the full `OpenChatTests` suite on a simulator). For a single-file fast loop during TDD, use `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/<TestClassName>` (swap the simulator name if `iPhone 16` isn't installed locally).

---

## File Structure

- **Modify** `OpenChat/Models/Conversation.swift` — add `messages(after:)` pure helper.
- **Create** `OpenChatTests/ConversationEditMessageTests.swift` — tests for `messages(after:)`, following the existing `ConversationTemporaryChatTests.swift` pattern (construct `Conversation`/`ChatMessage` in memory, no `ModelContext`).
- **Modify** `OpenChat/Features/Chat/ChatViewModel.swift` — add `editingMessageID` state and `beginEditing`/`cancelEditing`/`saveEdit` methods, next to `regenerateLastReply()`. No new automated tests (matches the existing no-test precedent for this class — see Global Constraints and the design doc's Testing section).
- **Modify** `OpenChat/Features/Chat/MessageBubbleView.swift` — add `isEditing`/`canEdit` params and `onBeginEdit`/`onCancelEdit`/`onSaveEdit` closures; add `EditChip`; restructure `userBubble` to branch into an `editingBubble` view when editing.
- **Modify** `OpenChat/Features/Chat/ChatView.swift` — `ChatMessageListView` passes the new params/closures to `MessageBubbleView`; `ChatComposerHost` disables `MessageComposerView` while `viewModel.editingMessageID != nil`.

---

### Task 1: `Conversation.messages(after:)`

**Files:**
- Modify: `OpenChat/Models/Conversation.swift:51-57`
- Test: `OpenChatTests/ConversationEditMessageTests.swift` (new)

**Interfaces:**
- Produces: `func messages(after message: ChatMessage) -> [ChatMessage]` on `Conversation` — returns the messages strictly after `message` in `sortedMessages` order; `[]` if `message` is last or not found. Consumed by `ChatViewModel.saveEdit` in Task 2.

- [ ] **Step 1: Write the failing tests**

Create `OpenChatTests/ConversationEditMessageTests.swift`:

```swift
import XCTest
@testable import OpenChat

final class ConversationEditMessageTests: XCTestCase {
    private func makeMessage(_ role: MessageRole, _ content: String, secondsOffset: Double) -> ChatMessage {
        ChatMessage(role: role, content: content, createdAt: Date(timeIntervalSince1970: secondsOffset))
    }

    func testMessagesAfterReturnsEmptyWhenMessageIsLast() throws {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let first = makeMessage(.user, "Hi", secondsOffset: 0)
        let second = makeMessage(.assistant, "Hello", secondsOffset: 1)
        first.conversation = conversation
        second.conversation = conversation
        conversation.messages = [first, second]

        XCTAssertTrue(conversation.messages(after: second).isEmpty)
    }

    func testMessagesAfterReturnsSuffixWhenMessageIsInMiddle() throws {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let first = makeMessage(.user, "Hi", secondsOffset: 0)
        let second = makeMessage(.assistant, "Hello", secondsOffset: 1)
        let third = makeMessage(.user, "Follow up", secondsOffset: 2)
        let fourth = makeMessage(.assistant, "Answer", secondsOffset: 3)
        for message in [first, second, third, fourth] {
            message.conversation = conversation
        }
        conversation.messages = [first, second, third, fourth]

        let result = conversation.messages(after: second)
        XCTAssertEqual(result.map(\.id), [third.id, fourth.id])
    }

    func testMessagesAfterReturnsEmptyWhenMessageNotInConversation() throws {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let first = makeMessage(.user, "Hi", secondsOffset: 0)
        first.conversation = conversation
        conversation.messages = [first]

        let outsider = makeMessage(.user, "Not here", secondsOffset: 5)

        XCTAssertTrue(conversation.messages(after: outsider).isEmpty)
    }

    func testMessagesAfterWithMultiplePairsReturnsOnlyTrailingOnes() throws {
        let conversation = Conversation(providerID: "openai", modelID: "gpt-4o")
        let messages = (0..<6).map { index -> ChatMessage in
            let role: MessageRole = index.isMultiple(of: 2) ? .user : .assistant
            return makeMessage(role, "Message \(index)", secondsOffset: Double(index))
        }
        for message in messages {
            message.conversation = conversation
        }
        conversation.messages = messages

        let result = conversation.messages(after: messages[2])
        XCTAssertEqual(result.map(\.id), messages[3...5].map(\.id))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/ConversationEditMessageTests`
Expected: FAIL to build — `value of type 'Conversation' has no member 'messages(after:)'`.

- [ ] **Step 3: Write minimal implementation**

In `OpenChat/Models/Conversation.swift`, add directly after `hasUserMessages` (after line 57):

```swift
    /// Messages strictly after `message` in conversation order.
    /// Empty if `message` is the last message or isn't found.
    func messages(after message: ChatMessage) -> [ChatMessage] {
        let sorted = sortedMessages
        guard let index = sorted.firstIndex(where: { $0.id == message.id }) else { return [] }
        let next = sorted.index(after: index)
        guard next < sorted.endIndex else { return [] }
        return Array(sorted[next...])
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/ConversationEditMessageTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Models/Conversation.swift OpenChatTests/ConversationEditMessageTests.swift
git commit -m "feat: add Conversation.messages(after:) helper for edit truncation"
```

---

### Task 2: `ChatViewModel` editing state + `saveEdit`

**Files:**
- Modify: `OpenChat/Features/Chat/ChatViewModel.swift:8-21` (add property), `:411-418` (add methods after `regenerateLastReply()`)

**Interfaces:**
- Consumes: `Conversation.messages(after:) -> [ChatMessage]` from Task 1; existing `private let conversation: Conversation`, `private let modelContext: ModelContext`, `private(set) var isStreaming`, `private func requestAssistantReply()`.
- Produces: `private(set) var editingMessageID: UUID?`, `func beginEditing(_ message: ChatMessage)`, `func cancelEditing()`, `func saveEdit(_ message: ChatMessage, newText: String)` — consumed by `MessageBubbleView`/`ChatView` wiring in Tasks 3 and 4.

No automated test for this task (see Global Constraints — `ChatViewModel` has no existing test coverage, same as `regenerateLastReply()`, since it depends on live network streaming). Verified manually in Task 4's simulator check.

- [ ] **Step 1: Add `editingMessageID` state**

In `OpenChat/Features/Chat/ChatViewModel.swift`, add after `private(set) var compactStatusMessage: String?` (line 20):

```swift
    private(set) var editingMessageID: UUID?
```

- [ ] **Step 2: Add `beginEditing`, `cancelEditing`, `saveEdit`**

In `OpenChat/Features/Chat/ChatViewModel.swift`, add immediately after `regenerateLastReply()` (after line 418, before `cancelStreaming()`):

```swift
    func beginEditing(_ message: ChatMessage) {
        guard !isStreaming, message.role == .user else { return }
        editingMessageID = message.id
    }

    func cancelEditing() {
        editingMessageID = nil
    }

    func saveEdit(_ message: ChatMessage, newText: String) {
        guard editingMessageID == message.id, !isStreaming else { return }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !message.imageAttachments.isEmpty else { return }

        message.content = trimmed

        let trailingMessages = conversation.messages(after: message)
        let trailingIDs = Set(trailingMessages.map(\.id))
        for trailing in trailingMessages {
            modelContext.delete(trailing)
        }
        conversation.messages.removeAll { trailingIDs.contains($0.id) }

        conversation.updatedAt = .now
        editingMessageID = nil

        requestAssistantReply()
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add OpenChat/Features/Chat/ChatViewModel.swift
git commit -m "feat: add editingMessageID, beginEditing, cancelEditing, saveEdit to ChatViewModel"
```

---

### Task 3: `MessageBubbleView` edit chip + inline editing UI

**Files:**
- Modify: `OpenChat/Features/Chat/MessageBubbleView.swift`

**Interfaces:**
- Consumes: existing `Theme.userBubble`, `Theme.bubbleCornerRadius`, `Haptics.light()`; new closures wired in from `ChatView.swift` in Task 4.
- Produces: new `MessageBubbleView` params `isEditing: Bool = false`, `canEdit: Bool = false`, `onBeginEdit: (() -> Void)? = nil`, `onCancelEdit: (() -> Void)? = nil`, `onSaveEdit: ((String) -> Void)? = nil` — consumed by `ChatMessageListView` in Task 4.

No automated test for this task — it's pure SwiftUI view layout with no testable logic beyond what Task 1/2 already cover. Verified manually in Task 4's simulator check (per the design doc's Testing section).

- [ ] **Step 1: Add new params to `MessageBubbleView`**

In `OpenChat/Features/Chat/MessageBubbleView.swift`, replace lines 6-25:

```swift
struct MessageBubbleView: View {
    let message: ChatMessage
    let providerTint: Color
    let providerSymbol: String
    var providerLogoAssetName: String? = nil
    var pendingCalendarActions: [CalendarActionProposal] = []
    var calendarActionStatus: String? = nil
    var isApplyingCalendarActions: Bool = false
    var onConfirmCalendarActions: (() -> Void)? = nil
    var onDismissCalendarActions: (() -> Void)? = nil
    var pendingMemoryProposals: [MemoryProposal] = []
    var memoryActionStatus: String? = nil
    var onConfirmMemoryProposals: (() -> Void)? = nil
    var onDismissMemoryProposals: (() -> Void)? = nil
    var isLastMessage: Bool = false
    let onRetry: () -> Void
    var isEditing: Bool = false
    var canEdit: Bool = false
    var onBeginEdit: (() -> Void)? = nil
    var onCancelEdit: (() -> Void)? = nil
    var onSaveEdit: ((String) -> Void)? = nil

    #if canImport(UIKit)
    @State private var previewAttachment: ChatImageAttachment?
    #endif
    @State private var draftText: String = ""
```

- [ ] **Step 2: Replace `userBubble` with an editing-aware version**

In `OpenChat/Features/Chat/MessageBubbleView.swift`, replace the `userBubble` computed property (original lines 47-63):

```swift
    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 8) {
                if !message.imageAttachments.isEmpty {
                    attachmentGallery(message.imageAttachments, alignment: .trailing)
                }
                if isEditing {
                    editingBubble
                } else {
                    if !message.content.isEmpty {
                        MarkdownMessageView(content: message.content, isUserMessage: true)
                            .equatable()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: Theme.bubbleCornerRadius, style: .continuous))
                    }
                    #if canImport(UIKit)
                    if canEdit {
                        EditChip {
                            draftText = message.content
                            onBeginEdit?()
                        }
                    }
                    #endif
                }
            }
        }
    }

    private var editingBubble: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextField("Edit message", text: $draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .tint(.white)
                .lineLimit(1...8)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: Theme.bubbleCornerRadius, style: .continuous))

            HStack(spacing: 10) {
                Button("Cancel") {
                    Haptics.light()
                    onCancelEdit?()
                }
                .buttonStyle(.bordered)

                Button("Save · Send") {
                    Haptics.light()
                    onSaveEdit?(draftText)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.imageAttachments.isEmpty)
            }
        }
    }
```

- [ ] **Step 3: Add `EditChip`**

In `OpenChat/Features/Chat/MessageBubbleView.swift`, add after the `CopyChip` struct (after original line 230, before `RegenerateChip`):

```swift
private struct EditChip: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: "pencil")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit message")
    }
}
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED. (`ChatView.swift` still passes only the old params at this point — all new params have defaults, so this compiles standalone.)

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Features/Chat/MessageBubbleView.swift
git commit -m "feat: add inline edit UI and edit chip to user message bubbles"
```

---

### Task 4: Wire editing through `ChatView`

**Files:**
- Modify: `OpenChat/Features/Chat/ChatView.swift:172-200` (`ChatComposerHost`), `:226-250` (`ChatMessageListView`'s `MessageBubbleView` call site)

**Interfaces:**
- Consumes: `ChatViewModel.editingMessageID`, `.beginEditing(_:)`, `.cancelEditing()`, `.saveEdit(_:newText:)` from Task 2; `MessageBubbleView`'s `isEditing`/`canEdit`/`onBeginEdit`/`onCancelEdit`/`onSaveEdit` params from Task 3.

No automated test for this task — it's SwiftUI wiring with no testable logic beyond Tasks 1/2. Verified manually per the design doc's Testing section (see Step 3 below).

- [ ] **Step 1: Disable the composer while editing**

In `OpenChat/Features/Chat/ChatView.swift`, in `ChatComposerHost.body`, wrap the existing `MessageComposerView(...)` call (lines 173-199) with `.disabled(...)`:

```swift
    var body: some View {
        MessageComposerView(
            text: $viewModel.composerText,
            attachments: $viewModel.pendingAttachments,
            supportsVision: viewModel.supportsVision,
            modelDisplayName: viewModel.currentModel?.displayName,
            isStreaming: viewModel.isStreaming,
            canUseWebSearch: viewModel.canUseWebSearch,
            isWebSearchArmed: viewModel.isWebSearchArmed,
            webSearchProviders: viewModel.configuredWebSearchProviders,
            selectedWebSearchProvider: viewModel.selectedWebSearchProvider,
            webSearchProviderName: viewModel.webSearchProviderName,
            webSearchLogoAssetName: viewModel.webSearchStoreActiveLogo,
            webSearchSymbolName: viewModel.webSearchStoreActiveSymbol,
            webSearchTintHex: viewModel.webSearchStoreActiveTint,
            onSelectWebSearchProvider: viewModel.selectWebSearchProvider,
            onDisableWebSearch: viewModel.disableWebSearchForChat,
            showCompactChip: viewModel.canShowCompact,
            canCompact: viewModel.canCompactConversation,
            isCompacting: viewModel.isCompacting,
            onCompact: viewModel.compactConversation,
            hasChatRules: hasChatRules,
            canUseChatRules: canUseChatRules,
            conversation: conversation,
            skills: skills.map(SkillMatchable.init(skill:)),
            onSend: onSend,
            onStop: viewModel.cancelStreaming
        )
        .disabled(viewModel.editingMessageID != nil)
    }
```

- [ ] **Step 2: Pass edit params/closures to `MessageBubbleView`**

In `OpenChat/Features/Chat/ChatView.swift`, in `ChatMessageListView.body`'s `ForEach(sortedMessages)`, replace the `MessageBubbleView(...)` call (lines 226-250):

```swift
                        MessageBubbleView(
                            message: message,
                            providerTint: messageProvider.map { Color(hex: $0.tint) } ?? .accentColor,
                            providerSymbol: messageProvider?.symbolName ?? "sparkles",
                            providerLogoAssetName: messageProvider?.logoAssetName,
                            pendingCalendarActions: viewModel.pendingCalendarActionsByMessageID[message.id] ?? [],
                            calendarActionStatus: viewModel.calendarActionStatusByMessageID[message.id],
                            isApplyingCalendarActions: viewModel.isApplyingCalendarActions,
                            onConfirmCalendarActions: {
                                viewModel.confirmCalendarActions(for: message.id)
                            },
                            onDismissCalendarActions: {
                                viewModel.dismissCalendarActions(for: message.id)
                            },
                            pendingMemoryProposals: viewModel.pendingMemoryProposalsByMessageID[message.id] ?? [],
                            memoryActionStatus: viewModel.memoryActionStatusByMessageID[message.id],
                            onConfirmMemoryProposals: {
                                viewModel.confirmMemoryProposals(for: message.id)
                            },
                            onDismissMemoryProposals: {
                                viewModel.dismissMemoryProposals(for: message.id)
                            },
                            isLastMessage: message.id == lastMessageID,
                            onRetry: viewModel.regenerateLastReply,
                            isEditing: viewModel.editingMessageID == message.id,
                            canEdit: !viewModel.isStreaming,
                            onBeginEdit: {
                                viewModel.beginEditing(message)
                            },
                            onCancelEdit: {
                                viewModel.cancelEditing()
                            },
                            onSaveEdit: { newText in
                                viewModel.saveEdit(message, newText: newText)
                            }
                        )
                        .id(message.id)
```

- [ ] **Step 3: Build, then manually verify in the simulator**

Run: `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

Then launch the app in the simulator and manually verify (per the design doc's Testing section):
- A pencil edit chip appears under user messages; tapping it swaps the bubble for an inline text field pre-filled with the message text, with Cancel/Save · Send buttons below.
- Editing an early user message in a multi-turn conversation and tapping Save · Send: later messages (both user and assistant) disappear, and a new assistant reply streams in.
- Tapping Cancel leaves the original message and all history untouched.
- The edit chip is absent while the assistant is streaming a reply.
- The bottom composer is disabled (greyed out / non-interactive) while an edit is in progress.

- [ ] **Step 4: Commit**

```bash
git add OpenChat/Features/Chat/ChatView.swift
git commit -m "feat: wire message editing through ChatView and disable composer while editing"
```

---

## Self-Review

**Spec coverage:**
- Editable: user messages only → `beginEditing` guards `message.role == .user` (Task 2); `EditChip` only rendered in `userBubble` (Task 3). ✅
- No branching/version history, destructive save → `saveEdit` deletes `conversation.messages(after: message)` from both `modelContext` and the array (Task 2, using Task 1's helper). ✅
- No undo after save → not implemented anywhere; Cancel only discards the local `draftText` before saving (Task 3). ✅
- Edit chip styled like `CopyChip`/`RegenerateChip`, hidden while streaming → `EditChip` mirrors their exact modifier chain; `canEdit: !viewModel.isStreaming` gates visibility (Tasks 3, 4). ✅
- Inline multi-line field pre-filled with `message.content`, local `@State draftText` → Task 3, Step 1-2. ✅
- Cancel/Save · Send buttons styled like calendar/memory cards (`.bordered`/`.borderedProminent`) → Task 3, Step 2. ✅
- Save · Send disabled when empty and no attachments (mirrors `MessageComposerView.canSend`) → Task 3, Step 2 `.disabled(...)`. ✅
- Composer disabled while editing → Task 4, Step 1. ✅
- `ChatMessageListView` wiring with `isEditing`/`canEdit` + three closures → Task 4, Step 2. ✅
- Tests for `messages(after:)`: last message, middle message, not-found message, multiple pairs → Task 1, Step 1 (4 tests, all four cases covered). ✅
- `ChatViewModel` has no new test infra, matching existing precedent → explicitly noted in Task 2 and Global Constraints. ✅

**Placeholder scan:** No "TBD"/"TODO"/"similar to Task N" found; every step has complete, real code.

**Type consistency:** `messages(after:) -> [ChatMessage]` (Task 1) is called identically in Task 2's `saveEdit`. `editingMessageID: UUID?` (Task 2) is compared as `viewModel.editingMessageID == message.id` (Task 4) and as `editingMessageID == message.id` inside `saveEdit` (Task 2) — consistent `UUID?`/`UUID` comparison throughout. `MessageBubbleView`'s new params (`isEditing: Bool`, `canEdit: Bool`, `onBeginEdit: (() -> Void)?`, `onCancelEdit: (() -> Void)?`, `onSaveEdit: ((String) -> Void)?`, Task 3) match the argument types passed at the Task 4 call site exactly.

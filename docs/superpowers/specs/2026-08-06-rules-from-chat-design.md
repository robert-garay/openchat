# Add Rules From Chat — Design

## Summary

Let the assistant propose new rules (global or chat-scoped) during a
conversation, mirroring the existing Memory feature's fenced-text
proposal flow. The user reviews and confirms scope before a proposed
rule is saved (unless confirmation is explicitly disabled in
settings). Off by default.

## Background

OpenChat already has three "model proposes something, user
confirms" flows, all in `ChatViewModel.swift`:

1. **Memory** (`MemoryStore`, `MemoryActionParser`) — the model writes
   a fenced ```` ```openchat-memory ```` block (or `<memory_proposal>`
   tag) in its reply. After streaming, `captureMemoryProposals`
   parses it, and either stages it for confirmation
   (`pendingMemoryProposalsByMessageID`, shown as an inline Save/Discard
   card in `MessageBubbleView`) or auto-saves it, depending on
   `MemoryStore.requireConfirmation`. Gated end-to-end by
   `MemoryStore.useInChats` (off by default) — only when true does the
   model even receive `MemoryStore.modelInstruction()` in the system
   prompt.
2. **Calendar** (`CalendarActionParser`) — same fenced-block shape,
   no scope concept, gated on calendar-edit permission rather than a
   user toggle.
3. **Skills** (`SkillToolService`) — a *true* tool-calling definition
   (`create_skill`, requires `model.supportsTools == true`, no text
   fallback). A proposal opens a full review sheet (`SkillEditorView`)
   before saving, rather than an inline Save/Discard card.

Rules (`RuleItem`, `RulesStore`) already model global vs. chat scope:
`RuleItem.conversation == nil` means global, a set value means
chat-scoped, and `RulesStore.save(content:modelContext:conversation:)`
already accepts an optional conversation. There is currently no path
from the LLM into rule creation at all — rules can only be added via
`ChatRulesSheet` (chat-scoped) or `RulesSettingsView` (global), both
calling `RulesStore.save` directly from SwiftUI.

The one problem Memory/Calendar don't have to solve: **scope**. A
rule proposal needs to say whether it's global or chat-specific, and
that's meaningfully higher-stakes than a memory fact (a global rule
silently changes every future conversation), so it needs a
deliberate confirmation step rather than a one-tap inline card.

## Scope

- New fenced-text proposal convention (` ```openchat-rule ` /
  `<rule_proposal>`), parsed by a new `RuleActionParser`, following
  the Memory/Calendar text-convention pattern rather than true tool
  calling — this works on every model, not just tool-calling-capable
  ones.
- Every proposal always includes a `scope` field (`"global"` or
  `"chat"`); the model is instructed to ask the user conversationally
  when scope is unclear, rather than the app guessing.
- Confirmation always opens a review sheet with an editable scope
  picker (mirroring `SkillEditorView`'s review-before-save flow), not
  an inline Save/Discard card — because scope carries real
  consequences.
- New `RulesStore.allowProposalsFromChat` toggle (default off) gates
  the entire capability, independent of the existing
  `useGlobalRules`/`useChatRules` toggles (which only control whether
  *existing* rules get injected into the prompt).
- New `RulesStore.requireConfirmation` toggle (default on), mirroring
  `MemoryStore.requireConfirmation`. When off, proposals auto-save
  using the model's stated scope.

### Out of scope

- No new tool-calling definition — text-fence convention only.
- No changes to `RuleItem`/`RulesStore`'s existing schema or save
  logic — reused as-is.
- No batch "confirm all" UI — each proposal is reviewed individually,
  same granularity as skill proposals.
- No changes to how existing rules are injected into the system
  prompt (`ChatSystemPromptBuilder`, `useGlobalRules`/`useChatRules`)
  — unrelated to proposing new ones.

## Architecture

### 1. `RuleProposal` (new file `OpenChat/Services/RuleProposal.swift`)

```swift
enum RuleScope: String, Sendable {
    case global
    case chat
}

struct RuleProposal: Equatable, Identifiable, Sendable {
    var id = UUID()
    var content: String
    var scope: RuleScope
}
```

### 2. `RuleActionParser` (new file `OpenChat/Services/RuleActionParser.swift`)

Mirrors `MemoryActionParser`'s shape (fence + tag regex, `strippingFences`),
but the decode step is stricter: unlike memory's bare-line fallback,
a block missing `content` or an unrecognized `scope` is dropped
entirely, since scope isn't safe to guess.

```swift
private static let fence = #"```openchat-rule\s*([\s\S]*?)```"#
private static let tag = #"<rule_proposal>([\s\S]*?)</rule_proposal>"#
```

JSON body shapes:
- Single: `{"content": "...", "scope": "global"|"chat"}`
- Multiple: `{"rules": [{"content": "...", "scope": "..."}, ...]}`

`strippingFences(from:)` added to `MessageBubbleView.displayContent`'s
existing strip chain (alongside `MemoryActionParser`/`CalendarActionParser`).

### 3. `RulesStore` additions

```swift
private let allowProposalsKey = "com.openchat.rules.allowProposalsFromChat"
private let requireConfirmationKey = "com.openchat.rules.requireConfirmation"

private(set) var allowProposalsFromChat: Bool  // default false
private(set) var requireConfirmation: Bool     // default true

func setAllowProposalsFromChat(_ value: Bool) { ... }
func setRequireConfirmation(_ value: Bool) { ... }

nonisolated static func shouldAllowRuleProposals(
    isTemporary: Bool,
    allowProposalsFromChat: Bool
) -> Bool {
    allowProposalsFromChat && !isTemporary
}

nonisolated static func modelInstruction() -> String {
    """
    The user enabled rule proposals in OpenChat. If you want to establish a standing \
    instruction, propose it using ```openchat-rule\\n{"content":"...","scope":"global"|"chat"}\\n```. \
    Always include scope — if it's not clear from context whether this should apply to just \
    this chat or to every chat, ask the user before proposing it. Saved after confirmation \
    unless disabled.
    """
}
```

### 4. `ChatViewModel` wiring

- `shouldAllowRuleProposals` computed property (init-time capture of
  `rulesStore.allowProposalsFromChat` + `conversation.isTemporary`),
  same shape as the existing `shouldUseMemory` (`ChatViewModel.swift:84`).
- In the streaming `Task` (`ChatViewModel.swift:539-548` region), add:
  ```swift
  if shouldAllowRuleProposals {
      middleSections.append(RulesStore.modelInstruction())
  }
  ```
- New state: `pendingRuleProposalsByMessageID: [UUID: [RuleProposal]]`,
  `ruleActionStatusByMessageID: [UUID: String]`.
- New `captureRuleProposals(from:)`, called alongside
  `captureCalendarProposals`/`captureMemoryProposals` after streaming
  ends:
  ```swift
  private func captureRuleProposals(from message: ChatMessage) {
      guard shouldAllowRuleProposals else { return }
      let proposals = RuleActionParser.parse(message.content)
      guard !proposals.isEmpty else { return }
      if rulesStore.requireConfirmation {
          pendingRuleProposalsByMessageID[message.id] = proposals
      } else {
          saveRuleProposals(proposals, messageID: message.id)
      }
  }

  private func saveRuleProposals(_ proposals: [RuleProposal], messageID: UUID) {
      var saved = 0
      for proposal in proposals {
          do {
              let conversationForScope = proposal.scope == .global ? nil : conversation
              _ = try rulesStore.save(content: proposal.content, modelContext: modelContext, conversation: conversationForScope)
              saved += 1
          } catch {
              ruleActionStatusByMessageID[messageID] = error.localizedDescription
              return
          }
      }
      if saved > 0 {
          try? modelContext.save()
          ruleActionStatusByMessageID[messageID] = "Rule saved."
      }
  }

  func dismissRuleProposals(for messageID: UUID) {
      pendingRuleProposalsByMessageID[messageID] = nil
  }

  func clearRuleProposalAfterReview(for messageID: UUID, proposalID: UUID) {
      guard var proposals = pendingRuleProposalsByMessageID[messageID] else { return }
      proposals.removeAll { $0.id == proposalID }
      if proposals.isEmpty {
          pendingRuleProposalsByMessageID[messageID] = nil
      } else {
          pendingRuleProposalsByMessageID[messageID] = proposals
      }
  }
  ```
  Removes only the reviewed proposal — any remaining proposals for
  this message stay pending, so reviewing one of several proposals in
  a message no longer discards the rest.
  (`RuleProposal.scope` is non-optional after parsing, so there's no
  runtime "missing scope" case to default — the parser already
  dropped those blocks.)

### 5. UI

**`MessageBubbleView`** — new bindings mirroring the skill-proposal
trio. Note `MessageBubbleView` doesn't currently hold a `conversation`
reference (verified: no match for `conversation` in the file today),
so this also adds one — the enclosing view (the messages-list struct
in `ChatView.swift`, which already holds `let conversation: Conversation`
at line 209) already has it available to pass down at the existing
`MessageBubbleView(...)` call site (`ChatView.swift:243-257` region):
```swift
let conversation: Conversation
var pendingRuleProposals: [RuleProposal] = []
var ruleActionStatus: String? = nil
var onDismissRuleProposals: (() -> Void)? = nil
var onRuleProposalSaved: (() -> Void)? = nil
```
New `ruleProposalCard`, structurally like `skillProposalCard`:
```swift
private var ruleProposalCard: some View {
    VStack(alignment: .leading, spacing: 10) {
        Label("New rule proposed", systemImage: "list.bullet.clipboard")
            .font(.subheadline.weight(.semibold))
        ForEach(pendingRuleProposals) { proposal in
            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.content)
                    .font(.caption)
                Text(proposal.scope == .global ? "Global" : "This chat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        HStack {
            Button("Review") { reviewingRuleProposal = pendingRuleProposals.first }
                .buttonStyle(.borderedProminent)
            Button("Discard") { onDismissRuleProposals?() }
                .buttonStyle(.bordered)
        }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    .sheet(item: $reviewingRuleProposal) { proposal in
        RuleReviewSheet(proposal: proposal, conversation: conversation, onSaved: onRuleProposalSaved)
    }
}
```
Wired into the body alongside the existing calendar/memory/skill
card conditionals, with a status-line fallback
(`ruleActionStatus`) for the auto-save (confirmation-off) path.

**`RuleReviewSheet`** (new file `OpenChat/Features/Chat/RuleReviewSheet.swift`,
structurally like `RuleEditorSheet` in `RulesSettingsView.swift` plus
a scope picker):
```swift
struct RuleReviewSheet: View {
    let proposal: RuleProposal
    let conversation: Conversation
    let onSaved: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(RulesStore.self) private var rulesStore
    @Environment(\.modelContext) private var modelContext
    @State private var text = ""
    @State private var scope: RuleScope = .chat
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Rule", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                    Picker("Scope", selection: $scope) {
                        Text("This chat").tag(RuleScope.chat)
                        Text("Global").tag(RuleScope.global)
                    }
                    .pickerStyle(.segmented)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Review rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            _ = try rulesStore.save(
                                content: text,
                                modelContext: modelContext,
                                conversation: scope == .global ? nil : conversation
                            )
                            try modelContext.save()
                            onSaved?()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { text = proposal.content; scope = proposal.scope }
        }
    }
}
```

**`RulesSettingsView`** — two new toggles in the existing top
`Section`, same layout as `MemorySettingsView`:
```swift
Toggle("Allow assistant to propose rules", isOn: Binding(
    get: { rulesStore.allowProposalsFromChat },
    set: { rulesStore.setAllowProposalsFromChat($0) }
))
Toggle("Require confirmation", isOn: Binding(
    get: { rulesStore.requireConfirmation },
    set: { rulesStore.setRequireConfirmation($0) }
))
.disabled(!rulesStore.allowProposalsFromChat)
```
Footer text extended to cover the new toggles: "Global rules apply to
every chat when enabled. Chat rules are per-conversation instructions
(edited from the chat composer) and only apply when enabled. Both are
off by default. When the assistant is allowed to propose rules, it can
suggest new global or chat rules during a conversation for you to
review before they're saved."

**`ChatView`** — pass-through wiring for
`pendingRuleProposalsByMessageID`/`ruleActionStatusByMessageID` into
`MessageBubbleView`, and `onDismissRuleProposals`/`onRuleProposalSaved`
closures calling `viewModel.dismissRuleProposals`/`clearRuleProposalAfterReview`,
same shape as the existing memory/skill wiring at `ChatView.swift:243-257`.

## Error Handling

- `RuleActionParser`: malformed JSON, missing `content`, or an
  unrecognized `scope` value → block dropped silently (no user-facing
  error), consistent with Memory's decode-failure behavior.
- `RuleReviewSheet` save failure (e.g. empty content after trimming)
  → inline error text, same as `RuleEditorSheet`.
- Auto-save path (confirmation off) failure → `ruleActionStatusByMessageID`
  set to the error's `localizedDescription`, shown as the status line
  instead of "Rule saved." — mirrors `saveMemoryProposals`.
- No new error handling needed for the settings toggles — same
  UserDefaults-backed pattern as every other store toggle in the app.

## Testing

- `RuleActionParserTests` (new file, mirrors `MemoryActionParserTests.swift`):
  - Fence and tag parsing for single-rule JSON.
  - `rules` array parsing for multiple proposals.
  - Malformed JSON → empty result.
  - Missing `content` → dropped.
  - Missing/invalid `scope` → dropped (no fallback guess).
  - Dedupe of identical `(content, scope)` pairs.
  - `strippingFences(from:)` removes both fence and tag forms and
    collapses resulting blank lines.
- `RulesStoreTests` additions:
  - `allowProposalsFromChat`/`requireConfirmation` default values
    and persistence across store re-init (same pattern as existing
    `useGlobalRules`/`useChatRules` tests, if present, or as
    `MemoryStore`'s toggle tests).
  - `shouldAllowRuleProposals` truth table, including the
    `isTemporary` override.
- Manual verification in the simulator (this app has no existing unit
  test coverage for `MessageBubbleView` or `ChatViewModel`'s streaming
  paths — consistent with prior specs in this repo):
  - Enable "Allow assistant to propose rules," ask the assistant to
    "always respond in bullet points" → confirm it either asks for
    scope or proposes with an explicit scope, and the review sheet
    opens with the right content/scope pre-filled.
  - Save as "This chat" → confirm the rule appears under the chat's
    rule list and is injected into that chat's system prompt on the
    next turn, but not other chats.
  - Save as "Global" → confirm it appears in `RulesSettingsView` and
    is injected into every chat's system prompt.
  - Turn off "Require confirmation" → confirm a new proposal saves
    automatically and shows the "Rule saved." status line, no sheet.
  - Discard a proposal → confirm nothing is saved and the card is
    replaced by nothing (no status line).
  - Ambiguous request phrased without indicating scope → confirm the
    model asks a clarifying question in chat before proposing (this
    depends on model instruction-following; verify with at least one
    tool-calling-capable model and one text-only model, since this
    feature intentionally works on both).

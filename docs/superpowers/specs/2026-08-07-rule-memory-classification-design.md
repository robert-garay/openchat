# Rule vs. Memory Classification & Proposal Hygiene — Design

## Background

OpenChat's in-app assistant can propose two kinds of standing instructions during
chat: **Rules** (`RulesStore`, `` ```openchat-rule `` fenced blocks, full-sheet
confirmation UI) and **Memory** (`MemoryStore`, `` ```openchat-memory `` fenced
blocks, inline-card confirmation UI). Today the model has no explicit criteria for
choosing between the two — each store's `modelInstruction()` describes its own
mechanics but not when to prefer it over the other, so the end user effectively has
to steer the model toward the right one.

Two bugs were found in the same code paths during this work:

1. **Streaming fence flash**: while a `` ```openchat-rule `` or `` ```openchat-memory ``
   block is still streaming in (fence not yet closed), the raw fenced text renders
   visibly in the chat bubble for a moment before disappearing once the closing
   fence arrives, then reappears as a proposal card once capture runs at stream end.
   This happens for both Rule and Memory identically, and happens even when
   `requireConfirmation` is disabled.
2. **Rule context bleed**: when multiple rules are proposed in the same chat, the
   model tends to fold prior proposed-rule content into new proposals, producing
   rules that keep re-absorbing previous ones instead of being distinct. Memory
   already avoids an analogous problem via `MemoryStore.findSimilar` and an
   injected "existing memories" context block; Rules has neither.

## Goals

- Give the model explicit, example-driven criteria for choosing Rule vs. Memory,
  so end users never have to specify which one they mean.
- Bring Rules to parity with Memory's existing anti-duplication mechanisms
  (existing-items context injection + near-duplicate suppression), fixing the
  context-bleed bug.
- Fix the streaming fence-flash bug for both Rule and Memory blocks, including
  when confirmation is disabled.
- Keep the change contained: no data-model unification, no new confirmation UX,
  no secondary classification model call.

## Non-goals

- Merging the `openchat-rule` / `openchat-memory` conventions into one type with a
  `kind` field. The two systems keep separate parsers, stores, and confirmation
  UIs (full sheet vs. inline card) exactly as they are today.
- Adding a secondary LLM call or heuristic scorer to re-classify ambiguous
  proposals. If prompt-level classification proves insufficient later, that's a
  follow-up, not part of this change.
- Changing `requireConfirmation` defaults or toggle behavior.

## Design

### 1. Classification instructions

`RulesStore.modelInstruction()` (RulesStore.swift:117-128) and
`MemoryStore.modelInstruction()` (MemoryStore.swift:135-137) are rewritten to share
a consistent framing:

- **Rule** = an instruction about how the assistant should behave, act, or interact
  going forward — a behavior change (e.g., "always answer in bullet points",
  "never use corporate jargon").
- **Memory** = a fact about the user, their environment, or a situation worth
  recalling — world-model content, not a behavior change (e.g., "I use Xcode 16",
  "my team ships on Thursdays").

Each instruction includes 2-3 short contrastive examples so the distinction is
concrete rather than abstract, plus a one-line confidence bar: "only propose when
you're genuinely confident this is a standing instruction/durable fact — don't
propose speculative or one-off details." The bar is a wording nudge only, not a
structural gate, per the explicit direction not to raise the acceptance threshold
so high that it hurts UX.

### 2. Existing-rules context injection

Rules gains a `## Rules` context section analogous to Memory's `## Memory` block
(MemoryStore.swift:131-133), listing current global/chat rule content, injected the
same way into `middleSections` in `ChatViewModel.swift`. This lets the model see
what's already saved before proposing something new, directly addressing the
context-bleed bug: a prior rule is visible as already-saved state rather than
something the model re-derives and blends into the next proposal.

### 3. `RulesStore.findSimilar`

Port `MemoryStore.findSimilar` (MemoryStore.swift:146-149) to `RulesStore` with the
same normalized-content-comparison approach. When a new rule proposal is a
near-duplicate of an existing rule, it's suppressed rather than shown as a new
proposal. This is a structural backstop independent of prompt-level behavior —
belt-and-suspenders alongside the context injection in (2).

### 4. Streaming fence-flash fix

Root cause: `strippingFences` in both `RuleActionParser.swift:4` and
`MemoryActionParser.swift:4` only matches a *closed* fence
(`` ```openchat-rule\s*([\s\S]*?)``` ``). While the fence is open mid-stream, the
regex doesn't match, so `displayContent` (MessageBubbleView.swift:245-249) shows
the raw, unstripped fence text until the closing fence token arrives.

Fix: extend the stripping logic in both parsers to also match an **unclosed**
fence running to end-of-string, and strip it too, so nothing renders from the
moment the opening fence token appears until either the proposal card takes over
(confirmation enabled) or the content is auto-saved (confirmation disabled). This
must apply unconditionally — not gated on `requireConfirmation`, since the raw
fence should never be user-visible in either mode.

## Files touched

- `OpenChat/Services/RulesStore.swift` — rewritten `modelInstruction()`, new
  `findSimilar`, new existing-rules context builder
- `OpenChat/Services/MemoryStore.swift` — rewritten `modelInstruction()`
  (classification framing only; `findSimilar` already exists)
- `OpenChat/Services/RuleActionParser.swift`,
  `OpenChat/Services/MemoryActionParser.swift` — open-fence stripping
- `OpenChat/Features/Chat/ChatViewModel.swift` — wire the new Rules context block
  into `middleSections`, alongside Memory's existing wiring
- Tests: `OpenChatTests/RulesStoreTests.swift`, `OpenChatTests/MemoryStoreTests.swift`,
  plus parser tests for open-fence stripping (streaming-simulation: partial fence
  content must not render)

## Testing

- Unit tests for `RulesStore.findSimilar` mirroring `MemoryStoreTests`' existing
  near-duplicate coverage.
- Unit tests for both parsers' `strippingFences` covering: fully-closed fence
  (existing behavior, must not regress), open fence at end of string (new
  behavior — must strip through end of string), and non-fence text (must pass
  through unchanged).
- Existing `RulesStoreTests` / `MemoryStoreTests` suites must continue passing.
- Manual verification (noted as follow-up, consistent with this repo's existing
  practice of flagging simulator-only checks): confirm no visible flash while a
  rule/memory streams in, with confirmation both enabled and disabled.

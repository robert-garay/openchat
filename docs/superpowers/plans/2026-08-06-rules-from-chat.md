# Rules From Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the assistant propose new rules (global or chat-scoped) during a conversation, mirroring Memory's fenced-text proposal flow, with the user always reviewing scope in a dedicated sheet before a rule is saved (unless confirmation is disabled).

**Architecture:** A new fenced-text convention (`` ```openchat-rule ``` `` / `<rule_proposal>`) is parsed post-streaming by a new `RuleActionParser` into `RuleProposal` values that always carry a `scope` (`.global` or `.chat`). Capture and persistence live in `ChatViewModel`, gated by a new `RulesStore.allowProposalsFromChat` toggle (default off) independent of the existing `useGlobalRules`/`useChatRules` injection toggles. When `RulesStore.requireConfirmation` (default on) is true, proposals surface as a pending card in `MessageBubbleView` whose "Review" button opens a new `RuleReviewSheet` (editable content + segmented scope picker) that performs the actual save; when confirmation is off, proposals save automatically with no UI.

**Tech Stack:** Swift 6, SwiftUI, SwiftData (`@Observable`/`@MainActor` stores), XCTest.

## Global Constraints

- `RulesStore.allowProposalsFromChat` defaults to `false` and is independent of `useGlobalRules`/`useChatRules` (those only gate injecting *existing* rules into the system prompt).
- `RulesStore.requireConfirmation` defaults to `true`.
- Proposal mechanism is fenced-text/tag only — no `ChatToolDefinition`/tool-calling, so it works on every model regardless of `supportsTools`.
- Every parsed proposal must include a valid `scope` (`"global"` or `"chat"`); blocks missing or with an invalid scope are dropped silently — no bare-line fallback (unlike `MemoryActionParser`).
- The model instruction must tell the model to ask the user conversationally when scope is ambiguous, rather than guessing.
- Confirmation (when `requireConfirmation` is on) is always a review sheet with an editable scope picker — never an inline auto-confirm "Save" button like Memory's card.
- No changes to `RuleItem`, `RulesStore`'s CRUD/injection methods, or the existing `useGlobalRules`/`useChatRules` injection logic in `ChatViewModel`.
- No batch "confirm all" UI.
- Follow existing codebase convention: XCTest (`import XCTest` + `@testable import OpenChat`), not Swift Testing — the codebase has zero `import Testing` usage across 27 existing test files, and the two files this plan touches/extends (`MemoryActionParserTests.swift` pattern, `RulesStoreTests.swift`) are both XCTest.
- This app has no unit tests for `MessageBubbleView` or `ChatViewModel`'s streaming paths (established precedent, see `docs/superpowers/specs/2026-08-05-image-output-actions-design.md`) — UI wiring tasks are verified by `xcodebuild build` + a manual simulator checklist, not new UI tests.

---

## File Structure

- Create: `OpenChat/Services/RuleProposal.swift` — `RuleScope` enum + `RuleProposal` struct.
- Create: `OpenChat/Services/RuleActionParser.swift` — fence/tag parser, `strippingFences`.
- Create: `OpenChatTests/RuleActionParserTests.swift` — parser unit tests.
- Modify: `OpenChat/Services/RulesStore.swift` — add `allowProposalsFromChat`/`requireConfirmation` toggles + setters, `shouldAllowRuleProposals`, `modelInstruction()`.
- Modify: `OpenChatTests/RulesStoreTests.swift` — add tests for the two new toggles and `shouldAllowRuleProposals`.
- Create: `OpenChat/Features/Chat/RuleReviewSheet.swift` — review sheet (content + scope picker), does the actual save.
- Modify: `OpenChat/Features/Chat/ChatViewModel.swift` — pending/status dictionaries, `shouldAllowRuleProposals`, `middleSections` instruction injection, capture/save/dismiss/clear-after-review methods.
- Modify: `OpenChat/Features/Chat/MessageBubbleView.swift` — add `conversation` property, rule proposal bindings, `ruleProposalCard`, `displayContent` strip-chain update, `reviewingRuleProposal` sheet state.
- Modify: `OpenChat/Features/Chat/ChatView.swift` — pass `conversation` and the new bindings into the `MessageBubbleView(...)` call site.
- Modify: `OpenChat/Features/Settings/RulesSettingsView.swift` — two new toggles + footer text.

---

### Task 1: RuleProposal + RuleActionParser

**Files:**
- Create: `OpenChat/Services/RuleProposal.swift`
- Create: `OpenChat/Services/RuleActionParser.swift`
- Test: `OpenChatTests/RuleActionParserTests.swift`

**Interfaces:**
- Consumes: nothing (leaf files).
- Produces: `enum RuleScope: String, Sendable { case global, case chat }`; `struct RuleProposal: Equatable, Identifiable, Sendable { var id = UUID(); var content: String; var scope: RuleScope }`; `enum RuleActionParser { static func parse(_ markdown: String) -> [RuleProposal]; static func strippingFences(from markdown: String) -> String }`. Both consumed by `ChatViewModel` (Task 4) and `MessageBubbleView` (Task 5).

- [ ] **Step 1: Write the failing tests**

Create `OpenChatTests/RuleActionParserTests.swift`:

```swift
import XCTest
@testable import OpenChat

final class RuleActionParserTests: XCTestCase {
    func testParsesFenceSingleObject() {
        let proposals = RuleActionParser.parse(
            "```openchat-rule\n{\"content\":\"Always answer in Spanish.\",\"scope\":\"chat\"}\n```"
        )
        XCTAssertEqual(proposals.map(\.content), ["Always answer in Spanish."])
        XCTAssertEqual(proposals.map(\.scope), [.chat])
    }

    func testParsesTag() {
        let proposals = RuleActionParser.parse(
            "<rule_proposal>{\"content\":\"Be concise.\",\"scope\":\"global\"}</rule_proposal>"
        )
        XCTAssertEqual(proposals.map(\.content), ["Be concise."])
        XCTAssertEqual(proposals.map(\.scope), [.global])
    }

    func testParsesRulesArray() {
        let json = """
        {"rules":[{"content":"Use metric units.","scope":"global"},{"content":"Reply briefly.","scope":"chat"}]}
        """
        let proposals = RuleActionParser.parse("```openchat-rule\n\(json)\n```")
        XCTAssertEqual(proposals.map(\.content), ["Use metric units.", "Reply briefly."])
        XCTAssertEqual(proposals.map(\.scope), [.global, .chat])
    }

    func testDropsBlockMissingScope() {
        let proposals = RuleActionParser.parse("```openchat-rule\n{\"content\":\"No scope here.\"}\n```")
        XCTAssertTrue(proposals.isEmpty)
    }

    func testDropsBlockWithInvalidScope() {
        let proposals = RuleActionParser.parse(
            "```openchat-rule\n{\"content\":\"Bad scope.\",\"scope\":\"everywhere\"}\n```"
        )
        XCTAssertTrue(proposals.isEmpty)
    }

    func testDropsMalformedJSON() {
        let proposals = RuleActionParser.parse("```openchat-rule\nnot json\n```")
        XCTAssertTrue(proposals.isEmpty)
    }

    func testDropsEmptyContent() {
        let proposals = RuleActionParser.parse("```openchat-rule\n{\"content\":\"   \",\"scope\":\"chat\"}\n```")
        XCTAssertTrue(proposals.isEmpty)
    }

    func testDedupesByNormalizedContentKeepingFirst() {
        let markdown = """
        ```openchat-rule
        {"content":"Be concise.","scope":"chat"}
        ```
        <rule_proposal>{"content":"  be   CONCISE. ","scope":"global"}</rule_proposal>
        """
        let proposals = RuleActionParser.parse(markdown)
        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals.first?.scope, .chat)
    }

    func testStrippingFencesRemovesBothConventions() {
        let markdown = """
        Before
        ```openchat-rule
        {"content":"x","scope":"chat"}
        ```
        <rule_proposal>{"content":"y","scope":"global"}</rule_proposal>
        After
        """
        let stripped = RuleActionParser.strippingFences(from: markdown)
        XCTAssertFalse(stripped.contains("openchat-rule"))
        XCTAssertFalse(stripped.contains("rule_proposal"))
        XCTAssertTrue(stripped.hasPrefix("Before"))
        XCTAssertTrue(stripped.hasSuffix("After"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/RuleActionParserTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL to build — `RuleActionParser`/`RuleProposal`/`RuleScope` don't exist yet.

- [ ] **Step 3: Write minimal implementation**

Create `OpenChat/Services/RuleProposal.swift`:

```swift
import Foundation

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

Create `OpenChat/Services/RuleActionParser.swift`:

```swift
import Foundation

enum RuleActionParser {
    private static let fence = #"```openchat-rule\s*([\s\S]*?)```"#
    private static let tag = #"<rule_proposal>([\s\S]*?)</rule_proposal>"#

    static func parse(_ markdown: String) -> [RuleProposal] {
        dedupe(parseBlocks(markdown, fence) + parseBlocks(markdown, tag))
    }

    static func strippingFences(from markdown: String) -> String {
        var r = markdown
        for p in [fence, tag] {
            guard let rx = try? NSRegularExpression(pattern: p) else { continue }
            r = rx.stringByReplacingMatches(in: r, range: NSRange(r.startIndex..<r.endIndex, in: r), withTemplate: "")
        }
        return r.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseBlocks(_ markdown: String, _ pattern: String) -> [RuleProposal] {
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
        var out: [RuleProposal] = []
        rx.enumerateMatches(in: markdown, range: NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)) { m, _, _ in
            guard let m, let r = Range(m.range(at: 1), in: markdown) else { return }
            out += decode(String(markdown[r]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out
    }

    private struct RuleEntry: Decodable {
        var content: String
        var scope: String
    }

    private struct RuleEntryList: Decodable {
        var rules: [RuleEntry]
    }

    private static func decode(_ body: String) -> [RuleProposal] {
        let data = Data(body.utf8)
        if let entry = try? JSONDecoder().decode(RuleEntry.self, from: data) {
            return norm(entry)
        }
        if let container = try? JSONDecoder().decode(RuleEntryList.self, from: data) {
            return container.rules.compactMap { norm($0).first }
        }
        return []
    }

    private static func norm(_ entry: RuleEntry) -> [RuleProposal] {
        let content = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let scope = RuleScope(rawValue: entry.scope) else { return [] }
        return [RuleProposal(content: content, scope: scope)]
    }

    private static func dedupe(_ proposals: [RuleProposal]) -> [RuleProposal] {
        var seen = Set<String>()
        return proposals.filter {
            let key = normalize($0.content)
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func normalize(_ content: String) -> String {
        content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/RuleActionParserTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Services/RuleProposal.swift OpenChat/Services/RuleActionParser.swift OpenChatTests/RuleActionParserTests.swift
git commit -m "feat: add RuleProposal and RuleActionParser"
```

---

### Task 2: RulesStore proposal toggles + model instruction

**Files:**
- Modify: `OpenChat/Services/RulesStore.swift`
- Test: `OpenChatTests/RulesStoreTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces on `RulesStore`: `private(set) var allowProposalsFromChat: Bool`, `private(set) var requireConfirmation: Bool`, `func setAllowProposalsFromChat(_ value: Bool)`, `func setRequireConfirmation(_ value: Bool)`, `nonisolated static func shouldAllowRuleProposals(isTemporary: Bool, allowProposalsFromChat: Bool) -> Bool`, `nonisolated static func modelInstruction() -> String`. Consumed by `ChatViewModel` (Task 4) and `RulesSettingsView` (Task 7).

- [ ] **Step 1: Write the failing tests**

Add to `OpenChatTests/RulesStoreTests.swift` (inside the `RulesStoreTests` class, e.g. after `testTogglePersistence`):

```swift
    func testRuleProposalTogglesDefaultWhenKeysMissing() {
        XCTAssertFalse(store.allowProposalsFromChat)
        XCTAssertTrue(store.requireConfirmation)
        XCTAssertNil(defaults.object(forKey: "com.openchat.rules.allowProposalsFromChat"))
        XCTAssertNil(defaults.object(forKey: "com.openchat.rules.requireConfirmation"))
    }

    func testRuleProposalTogglePersistence() {
        store.setAllowProposalsFromChat(true)
        store.setRequireConfirmation(false)

        let reloaded = RulesStore(defaults: defaults)
        XCTAssertTrue(reloaded.allowProposalsFromChat)
        XCTAssertFalse(reloaded.requireConfirmation)
    }

    func testShouldAllowRuleProposals() {
        XCTAssertTrue(RulesStore.shouldAllowRuleProposals(isTemporary: false, allowProposalsFromChat: true))
        XCTAssertFalse(RulesStore.shouldAllowRuleProposals(isTemporary: true, allowProposalsFromChat: true))
        XCTAssertFalse(RulesStore.shouldAllowRuleProposals(isTemporary: false, allowProposalsFromChat: false))
        XCTAssertFalse(RulesStore.shouldAllowRuleProposals(isTemporary: true, allowProposalsFromChat: false))
    }

    func testModelInstructionMentionsFenceAndScope() {
        let instruction = RulesStore.modelInstruction()
        XCTAssertTrue(instruction.contains("openchat-rule"))
        XCTAssertTrue(instruction.contains("scope"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/RulesStoreTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL to build — `allowProposalsFromChat`/`requireConfirmation`/`shouldAllowRuleProposals`/`modelInstruction` don't exist on `RulesStore` yet.

- [ ] **Step 3: Write minimal implementation**

In `OpenChat/Services/RulesStore.swift`, add keys next to the existing ones (after line 13):

```swift
    private let allowProposalsFromChatKey = "com.openchat.rules.allowProposalsFromChat"
    private let requireConfirmationKey = "com.openchat.rules.requireConfirmation"
```

Add stored properties next to `useChatRules` (after line 19):

```swift
    private(set) var allowProposalsFromChat: Bool
    private(set) var requireConfirmation: Bool
```

In `init`, after the existing `useChatRules` default-handling block (after line 32, before the closing `}` of `init`):

```swift
        if defaults.object(forKey: allowProposalsFromChatKey) == nil {
            allowProposalsFromChat = false
        } else {
            allowProposalsFromChat = defaults.bool(forKey: allowProposalsFromChatKey)
        }
        if defaults.object(forKey: requireConfirmationKey) == nil {
            requireConfirmation = true
        } else {
            requireConfirmation = defaults.bool(forKey: requireConfirmationKey)
        }
```

Add setters next to `setUseChatRules` (after line 43):

```swift
    func setAllowProposalsFromChat(_ value: Bool) {
        allowProposalsFromChat = value
        defaults.set(value, forKey: allowProposalsFromChatKey)
    }

    func setRequireConfirmation(_ value: Bool) {
        requireConfirmation = value
        defaults.set(value, forKey: requireConfirmationKey)
    }
```

Add static helpers next to `injectionText(from:)` (after line 87, before `migrateLegacyGlobalRulesIfNeeded`):

```swift
    nonisolated static func shouldAllowRuleProposals(isTemporary: Bool, allowProposalsFromChat: Bool) -> Bool {
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/RulesStoreTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS (all `RulesStoreTests`, including the 4 new tests).

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Services/RulesStore.swift OpenChatTests/RulesStoreTests.swift
git commit -m "feat: add rule proposal toggles and model instruction to RulesStore"
```

---

### Task 3: RuleReviewSheet

**Files:**
- Create: `OpenChat/Features/Chat/RuleReviewSheet.swift`

**Interfaces:**
- Consumes: `RuleProposal`/`RuleScope` (Task 1), `RulesStore.save(content:modelContext:conversation:)` (existing), `Conversation` (existing model).
- Produces: `struct RuleReviewSheet: View { init(proposal: RuleProposal, conversation: Conversation, onSaved: (() -> Void)? = nil) }`. Consumed by `MessageBubbleView` (Task 5).

- [ ] **Step 1: Write the file**

Create `OpenChat/Features/Chat/RuleReviewSheet.swift`:

```swift
import SwiftUI
import SwiftData

struct RuleReviewSheet: View {
    @Environment(RulesStore.self) private var rulesStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let proposal: RuleProposal
    let conversation: Conversation
    var onSaved: (() -> Void)? = nil

    @State private var content = ""
    @State private var scope: RuleScope = .chat
    @State private var errorMessage: String?

    private var canSave: Bool { !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Rule", text: $content, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Rule")
                }
                Section {
                    Picker("Applies to", selection: $scope) {
                        Text("This chat").tag(RuleScope.chat)
                        Text("Every chat").tag(RuleScope.global)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Every chat rules apply globally, everywhere. This chat rules apply only to this conversation.")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Review Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                content = proposal.content
                scope = proposal.scope
            }
        }
    }

    private func save() {
        do {
            _ = try rulesStore.save(
                content: content,
                modelContext: modelContext,
                conversation: scope == .global ? nil : conversation
            )
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        Haptics.success()
        onSaved?()
        dismiss()
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED (the file compiles standalone even though nothing references it yet).

- [ ] **Step 3: Commit**

```bash
git add OpenChat/Features/Chat/RuleReviewSheet.swift
git commit -m "feat: add RuleReviewSheet for reviewing rule proposals"
```

---

### Task 4: ChatViewModel wiring

**Files:**
- Modify: `OpenChat/Features/Chat/ChatViewModel.swift`

**Interfaces:**
- Consumes: `RuleProposal`, `RuleActionParser.parse(_:)` (Task 1); `rulesStore.allowProposalsFromChat`, `rulesStore.requireConfirmation`, `RulesStore.shouldAllowRuleProposals(isTemporary:allowProposalsFromChat:)`, `RulesStore.modelInstruction()`, `rulesStore.save(content:modelContext:conversation:)` (Task 2).
- Produces: `private(set) var pendingRuleProposalsByMessageID: [UUID: [RuleProposal]]`, `private(set) var ruleActionStatusByMessageID: [UUID: String]`, `func dismissRuleProposals(for messageID: UUID)`, `func clearRuleProposalAfterReview(for messageID: UUID)`. Consumed by `MessageBubbleView`/`ChatView` (Tasks 5-6).

- [ ] **Step 1: Add pending/status state**

In `OpenChat/Features/Chat/ChatViewModel.swift`, add two new dictionaries next to the skill ones (after line 20, `private(set) var skillActionStatusByMessageID: [UUID: String] = [:]`):

```swift
    private(set) var pendingRuleProposalsByMessageID: [UUID: [RuleProposal]] = [:]
    private(set) var ruleActionStatusByMessageID: [UUID: String] = [:]
```

- [ ] **Step 2: Add the gating computed property**

Add next to `shouldUseMemory` (after line 85, the closing `}` of that computed var):

```swift
    private var shouldAllowRuleProposals: Bool {
        RulesStore.shouldAllowRuleProposals(
            isTemporary: conversation.isTemporary,
            allowProposalsFromChat: rulesStore.allowProposalsFromChat
        )
    }
```

- [ ] **Step 3: Add dismiss/clear-after-review methods**

Add next to `clearSkillProposalAfterReview`/`dismissSkillProposals` (after line 349, the closing `}` of `dismissSkillProposals`):

```swift
    /// Clears a pending rule proposal after the user saved it via the review sheet
    /// (RuleReviewSheet performs the actual save; this only clears the bookkeeping).
    func clearRuleProposalAfterReview(for messageID: UUID) {
        pendingRuleProposalsByMessageID[messageID] = nil
        ruleActionStatusByMessageID[messageID] = "Rule saved."
        Haptics.success()
    }

    func dismissRuleProposals(for messageID: UUID) {
        pendingRuleProposalsByMessageID[messageID] = nil
        ruleActionStatusByMessageID[messageID] = "Rule discarded."
        Haptics.light()
    }
```

- [ ] **Step 4: Inject the model instruction into the streaming prompt**

In the streaming `Task` block, after the `shouldUseMemory` block that appends `MemoryStore.modelInstruction()` (after line 548, the closing `}` of `if shouldUseMemory { ... }`):

```swift
                if shouldAllowRuleProposals {
                    middleSections.append(RulesStore.modelInstruction())
                }
```

- [ ] **Step 5: Capture rule proposals after streaming ends**

After the existing `captureMemoryProposals(from: assistantMessage)` call (line 666):

```swift
                captureRuleProposals(from: assistantMessage)
```

- [ ] **Step 6: Add capture/save private methods**

Add next to `saveMemoryProposals` (after line 717, the closing `}` of `saveMemoryProposals`, before `captureSkillProposals`):

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
                _ = try rulesStore.save(
                    content: proposal.content,
                    modelContext: modelContext,
                    conversation: proposal.scope == .global ? nil : conversation
                )
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
```

- [ ] **Step 7: Verify it builds**

Run: `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit**

```bash
git add OpenChat/Features/Chat/ChatViewModel.swift
git commit -m "feat: wire rule proposal capture and save into ChatViewModel"
```

---

### Task 5: MessageBubbleView wiring

**Files:**
- Modify: `OpenChat/Features/Chat/MessageBubbleView.swift`

**Interfaces:**
- Consumes: `RuleProposal`/`RuleScope` (Task 1), `RuleActionParser.strippingFences(from:)` (Task 1), `RuleReviewSheet(proposal:conversation:onSaved:)` (Task 3), `Conversation` (existing).
- Produces: new required `let conversation: Conversation` init parameter and new optional bindings on `MessageBubbleView` — `pendingRuleProposals: [RuleProposal]`, `ruleActionStatus: String?`, `onDismissRuleProposals: (() -> Void)?`, `onRuleProposalSaved: (() -> Void)?`. Consumed by the call site in `ChatView.swift` (Task 6).

- [ ] **Step 1: Add the `conversation` property**

In `OpenChat/Features/Chat/MessageBubbleView.swift`, add right after `let message: ChatMessage` (line 8):

```swift
    let conversation: Conversation
```

- [ ] **Step 2: Add rule proposal bindings**

Add right after `var onSkillProposalSaved: (() -> Void)? = nil` (line 24):

```swift
    var pendingRuleProposals: [RuleProposal] = []
    var ruleActionStatus: String? = nil
    var onDismissRuleProposals: (() -> Void)? = nil
    var onRuleProposalSaved: (() -> Void)? = nil
```

- [ ] **Step 3: Add the sheet-presentation state**

Add right after `@State private var reviewingSkillProposal: SkillProposal?` (line 39):

```swift
    @State private var reviewingRuleProposal: RuleProposal?
```

- [ ] **Step 4: Extend the fence-stripping chain**

Replace `displayContent` (lines 231-233):

```swift
    private var displayContent: String {
        RuleActionParser.strippingFences(
            from: MemoryActionParser.strippingFences(from: CalendarActionParser.strippingFences(from: message.content))
        )
    }
```

- [ ] **Step 5: Render the rule proposal card**

In the assistant `VStack` body, right after the skill proposal block (after line 215, the closing `}` of the `if !pendingSkillProposals.isEmpty { ... } else if let skillActionStatus ... }` block, before the `if let errorMessage = message.errorMessage` block):

```swift
                if !pendingRuleProposals.isEmpty {
                    ruleProposalCard
                } else if let ruleActionStatus, !ruleActionStatus.isEmpty {
                    Text(ruleActionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
```

- [ ] **Step 6: Add the `ruleProposalCard` computed view**

Add right after `skillProposalCard` (after line 326, its closing `}`):

```swift
    private var ruleProposalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("New rule proposed", systemImage: "list.bullet.rectangle")
                .font(.subheadline.weight(.semibold))
            ForEach(pendingRuleProposals) { proposal in
                VStack(alignment: .leading, spacing: 2) {
                    Text(proposal.content)
                        .font(.caption)
                    Text(proposal.scope == .global ? "Every chat" : "This chat")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Review") {
                    reviewingRuleProposal = pendingRuleProposals.first
                }
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

- [ ] **Step 7: Verify it builds**

Run: `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`
Expected: BUILD FAILS — `MessageBubbleView.init` now requires `conversation:`, which the call site in `ChatView.swift` doesn't yet provide. This confirms the new parameter is wired correctly; Task 6 fixes the call site.

- [ ] **Step 8: Commit**

```bash
git add OpenChat/Features/Chat/MessageBubbleView.swift
git commit -m "feat: add rule proposal card and review sheet to MessageBubbleView"
```

---

### Task 6: ChatView call-site wiring

**Files:**
- Modify: `OpenChat/Features/Chat/ChatView.swift`

**Interfaces:**
- Consumes: `MessageBubbleView`'s new `conversation`/`pendingRuleProposals`/`ruleActionStatus`/`onDismissRuleProposals`/`onRuleProposalSaved` parameters (Task 5); `viewModel.pendingRuleProposalsByMessageID`, `viewModel.ruleActionStatusByMessageID`, `viewModel.dismissRuleProposals(for:)`, `viewModel.clearRuleProposalAfterReview(for:)` (Task 4).
- Produces: nothing new (terminal wiring task).

- [ ] **Step 1: Pass `conversation` into the call site**

In `OpenChat/Features/Chat/ChatView.swift`, in `ChatMessageListView.body`, add right after `message: message,` (line 230):

```swift
                            conversation: conversation,
```

(`conversation` is already in scope — `ChatMessageListView` holds `let conversation: Conversation` at line 209.)

- [ ] **Step 2: Pass the rule proposal bindings**

Add right after the skill proposal bindings block (after line 258, the closing `}` of `onSkillProposalSaved: { viewModel.clearSkillProposalAfterReview(for: message.id) }`, before `isLastMessage: message.id == lastMessageID,`):

```swift
                            pendingRuleProposals: viewModel.pendingRuleProposalsByMessageID[message.id] ?? [],
                            ruleActionStatus: viewModel.ruleActionStatusByMessageID[message.id],
                            onDismissRuleProposals: {
                                viewModel.dismissRuleProposals(for: message.id)
                            },
                            onRuleProposalSaved: {
                                viewModel.clearRuleProposalAfterReview(for: message.id)
                            },
```

- [ ] **Step 3: Verify it builds**

Run: `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add OpenChat/Features/Chat/ChatView.swift
git commit -m "feat: wire rule proposal state from ChatViewModel into MessageBubbleView"
```

---

### Task 7: RulesSettingsView toggles

**Files:**
- Modify: `OpenChat/Features/Settings/RulesSettingsView.swift`

**Interfaces:**
- Consumes: `rulesStore.allowProposalsFromChat`, `rulesStore.setAllowProposalsFromChat(_:)`, `rulesStore.requireConfirmation`, `rulesStore.setRequireConfirmation(_:)` (Task 2).
- Produces: nothing new (terminal UI task).

- [ ] **Step 1: Add the two toggles and update the footer**

In `OpenChat/Features/Settings/RulesSettingsView.swift`, replace the top `Section` (lines 22-35):

```swift
            Section {
                Toggle("Use global rules in chats", isOn: Binding(
                    get: { rulesStore.useGlobalRules },
                    set: { rulesStore.setUseGlobalRules($0) }
                ))
                Toggle("Use chat rules", isOn: Binding(
                    get: { rulesStore.useChatRules },
                    set: { rulesStore.setUseChatRules($0) }
                ))
                Toggle("Allow assistant to propose rules", isOn: Binding(
                    get: { rulesStore.allowProposalsFromChat },
                    set: { rulesStore.setAllowProposalsFromChat($0) }
                ))
                Toggle("Require confirmation", isOn: Binding(
                    get: { rulesStore.requireConfirmation },
                    set: { rulesStore.setRequireConfirmation($0) }
                ))
                .disabled(!rulesStore.allowProposalsFromChat)
            } footer: {
                Text(
                    "Global rules apply to every chat when enabled. Chat rules are per-conversation instructions (edited from the chat composer) and only apply when enabled. Both are off by default. When the assistant is allowed to propose rules, it can suggest new global or chat rules during a conversation for you to review before they're saved."
                )
            }
```

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run the full test suite**

Run: `./scripts/ci-test.sh`
Expected: All tests pass, including `RuleActionParserTests` and the updated `RulesStoreTests`.

- [ ] **Step 4: Commit**

```bash
git add OpenChat/Features/Settings/RulesSettingsView.swift
git commit -m "feat: add rule proposal toggles to Rules settings"
```

- [ ] **Step 5: Manual simulator verification**

Launch the app (`xcodebuild build` output or Xcode) and check:
1. Settings → Rules: "Allow assistant to propose rules" is off by default; "Require confirmation" is disabled (greyed out) while it's off.
2. Turn "Allow assistant to propose rules" on (confirmation stays on by default). Start a chat, ask the assistant to adopt a standing instruction (e.g. "always reply in bullet points, and remember that for every chat"). Confirm a rule-proposal card appears with "Review"/"Discard".
3. Tap "Review" → `RuleReviewSheet` opens with the proposed content and scope pre-filled ("Every chat" selected per the example above). Change nothing, tap Save → sheet dismisses, card is replaced by "Rule saved.", and Settings → Rules → Global rules shows the new rule.
4. Repeat, but this time ask for something ambiguous ("remember I like concise answers") without specifying scope — confirm the assistant asks a clarifying question in the chat rather than silently picking a scope.
5. Turn "Require confirmation" off, trigger another proposal — confirm it saves automatically with a "Rule saved." status line and no review sheet.
6. Turn "Allow assistant to propose rules" off — confirm the assistant no longer proposes rules even when asked, and existing `useGlobalRules`/`useChatRules` injection behavior (unrelated toggles) is unaffected.

---

## Self-Review

**Spec coverage:**
- Fenced-text convention, no tool-calling → Task 1.
- `RuleProposal`/`RuleScope`, scope always required, malformed/scope-less blocks dropped, no bare-line fallback, dedupe → Task 1.
- `allowProposalsFromChat` toggle (default off, independent of `useGlobalRules`/`useChatRules`), `requireConfirmation` toggle (default on), `shouldAllowRuleProposals`, `modelInstruction()` (tells model to ask when scope is ambiguous) → Task 2.
- Confirmation always opens a review sheet with editable scope picker, never inline auto-save → Task 3 (`RuleReviewSheet`) + Task 5 (`ruleProposalCard`'s "Review" button, no inline "Save").
- `ChatViewModel` capture/save/dismiss/clear-after-review + prompt injection + auto-save-when-confirmation-off path → Task 4.
- `MessageBubbleView` needing a new `conversation` property (verified absent from the file, verified available in `ChatMessageListView`) → Task 5 + Task 6.
- Settings toggles mirroring Memory's pattern → Task 7.
- Manual end-to-end verification including the "model asks for clarification" behavior → Task 7, Step 5.

**Placeholder scan:** No TBD/TODO markers; every step has literal code or an exact command.

**Type consistency:** `RuleProposal`/`RuleScope` (Task 1) → used identically in `RulesStore.save(conversation:)` calls (Task 2 existing method, Task 3, Task 4), `RuleActionParser.parse`/`strippingFences` (Task 1) → used identically in `ChatViewModel.captureRuleProposals` (Task 4) and `MessageBubbleView.displayContent` (Task 5). `pendingRuleProposalsByMessageID`/`ruleActionStatusByMessageID`/`dismissRuleProposals`/`clearRuleProposalAfterReview` (Task 4) → same names used in `ChatView.swift` (Task 6). `pendingRuleProposals`/`ruleActionStatus`/`onDismissRuleProposals`/`onRuleProposalSaved`/`conversation` (Task 5's `MessageBubbleView` parameters) → same names used at the Task 6 call site. `RuleReviewSheet(proposal:conversation:onSaved:)` (Task 3) → called with matching argument labels in Task 5.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-06-rules-from-chat.md`. Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?

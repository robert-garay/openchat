# Rule vs. Memory Classification & Proposal Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give OpenChat's in-app assistant explicit criteria for choosing Rule vs. Memory (so the end user never has to specify which), bring `RulesStore` to parity with `MemoryStore`'s anti-duplication mechanisms, and fix the streaming fence-flash bug for both proposal types.

**Architecture:** No data-model or architecture changes. Rewrite both stores' `modelInstruction()` strings with contrastive Rule/Memory framing and an anti-fan-out clause (don't restate a Skill/other proposal from the same turn). Port `MemoryStore.findSimilar`/near-duplicate-merge-on-save to `RulesStore`. Add a `RulesStore.contextSection(for:)` analogous to `MemoryStore.contextSection(for:)`, wired into `ChatViewModel`'s `middleSections`. Extend both `RuleActionParser.strippingFences` and `MemoryActionParser.strippingFences` to also strip unclosed (mid-stream) fences.

**Tech Stack:** Swift, SwiftUI, SwiftData, XCTest.

## Global Constraints

- No changes to `requireConfirmation` defaults or toggle behavior (spec Non-goals).
- No merging of `openchat-rule`/`openchat-memory` into one convention/type (spec Non-goals).
- No secondary LLM call or heuristic classifier (spec Non-goals).
- The "confidence bar" wording nudge must NOT raise the acceptance threshold structurally — it's phrasing only, per the user's explicit direction to preserve current UX.
- Existing `RulesStoreTests`/`MemoryStoreTests`/`RuleActionParserTests`/`MemoryActionParserTests` suites must continue passing (only `testModelInstructionMentionsFenceAndScope`'s asserted substrings are known-compatible with the new wording; verify, don't break).

---

### Task 1: `RulesStore` near-duplicate detection on save/update

**Files:**
- Modify: `OpenChat/Services/RulesStore.swift`
- Test: `OpenChatTests/RulesStoreTests.swift`

**Interfaces:**
- Consumes: existing `RuleItem` model (`content: String`, `conversation: Conversation?`, `updatedAt: Date`), existing `RulesStore.fetchItems(modelContext:) -> [RuleItem]` (global-only, i.e. `conversation == nil`), existing `Conversation.rules: [RuleItem]` relationship.
- Produces: `nonisolated static func normalizeContent(_ content: String) -> String` on `RulesStore` (same shape as `MemoryStore.normalizeContent`), used internally and by tests. `save(content:modelContext:conversation:)` and `updateContent(_:content:modelContext:)` now merge into a near-duplicate instead of creating a second item, scoped correctly (global rules only dedupe against global rules; a chat's rules only dedupe against that same chat's rules).

- [ ] **Step 1: Write the failing tests**

Add to `OpenChatTests/RulesStoreTests.swift` (inside the `RulesStoreTests` class, after `testCRUDAndInjectionText`):

```swift
    func testSaveMergesNearDuplicateGlobalRule() throws {
        let container = try ModelContainer(
            for: RuleItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let first = try store.save(content: "Always answer in bullet points.", modelContext: context)
        try context.save()

        let second = try store.save(content: "always   answer in bullet points.  ", modelContext: context)
        try context.save()

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.content, "always   answer in bullet points.")
        XCTAssertEqual(try store.fetchItems(modelContext: context).count, 1)
    }

    func testSaveKeepsDistinctRulesSeparate() throws {
        let container = try ModelContainer(
            for: RuleItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        _ = try store.save(content: "Always answer in bullet points.", modelContext: context)
        _ = try store.save(content: "Never use corporate jargon.", modelContext: context)
        try context.save()

        XCTAssertEqual(try store.fetchItems(modelContext: context).count, 2)
    }

    func testSaveKeepsChatScopedRuleSeparateFromGlobalRule() throws {
        let container = try ModelContainer(
            for: RuleItem.self, Conversation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let conversation = Conversation(providerID: "test-provider", modelID: "test-model")
        context.insert(conversation)

        let global = try store.save(content: "Be concise.", modelContext: context)
        let chatScoped = try store.save(content: "Be concise.", modelContext: context, conversation: conversation)
        try context.save()

        XCTAssertNotEqual(global.id, chatScoped.id)
        XCTAssertEqual(try store.fetchItems(modelContext: context).count, 1)
        XCTAssertEqual(conversation.rules.count, 1)
    }

    func testSaveMergesNearDuplicateWithinSameChat() throws {
        let container = try ModelContainer(
            for: RuleItem.self, Conversation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let conversation = Conversation(providerID: "test-provider", modelID: "test-model")
        context.insert(conversation)

        let first = try store.save(content: "Reply in Spanish.", modelContext: context, conversation: conversation)
        let second = try store.save(content: "reply in spanish.", modelContext: context, conversation: conversation)
        try context.save()

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(conversation.rules.count, 1)
    }

    func testUpdateContentMergesIntoNearDuplicate() throws {
        let container = try ModelContainer(
            for: RuleItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let first = try store.save(content: "Be concise.", modelContext: context)
        let second = try store.save(content: "Prefer metric units.", modelContext: context)
        try context.save()

        try store.updateContent(second, content: "be   CONCISE.", modelContext: context)
        try context.save()

        XCTAssertEqual(first.content, "be   CONCISE.")
        XCTAssertEqual(try store.fetchItems(modelContext: context).count, 1)
    }

    func testNormalizeContentCollapsesWhitespaceAndCase() {
        XCTAssertEqual(
            RulesStore.normalizeContent("  Always   Answer\nIn Spanish.  "),
            RulesStore.normalizeContent("always answer in spanish.")
        )
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/RulesStoreTests`
Expected: FAIL — `testSaveMergesNearDuplicateGlobalRule`, `testSaveKeepsChatScopedRuleSeparateFromGlobalRule`, `testSaveMergesNearDuplicateWithinSameChat`, and `testUpdateContentMergesIntoNearDuplicate` fail (duplicate items created instead of merged); `testNormalizeContentCollapsesWhitespaceAndCase` fails to compile (`normalizeContent` doesn't exist yet). `testSaveKeepsDistinctRulesSeparate` passes already (no regression risk, included for parity coverage).

- [ ] **Step 3: Implement `normalizeContent`, `findSimilar`, and wire into `save`/`updateContent`**

In `OpenChat/Services/RulesStore.swift`, replace the existing `save` method:

```swift
    @discardableResult
    func save(content: String, modelContext: ModelContext, conversation: Conversation? = nil) throws -> RuleItem {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RulesStoreError.emptyContent }

        let existing = try scopedItems(conversation: conversation, modelContext: modelContext)
        if let match = findSimilar(existing, trimmed) {
            match.content = trimmed
            match.updatedAt = .now
            return match
        }

        let item = RuleItem(content: trimmed, conversation: conversation)
        modelContext.insert(item)
        return item
    }
```

Replace the existing `updateContent` method:

```swift
    func updateContent(_ item: RuleItem, content: String, modelContext: ModelContext) throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RulesStoreError.emptyContent }

        let others = try scopedItems(conversation: item.conversation, modelContext: modelContext)
            .filter { $0.id != item.id }
        if let match = findSimilar(others, trimmed) {
            modelContext.delete(item)
            match.content = trimmed
            match.updatedAt = .now
            return
        }

        item.content = trimmed
        item.updatedAt = .now
    }
```

Add two new private/static helpers right after `injectionText(from:)` (after line 111, before `shouldAllowRuleProposals`):

```swift
    /// Rules already saved in the same scope as `conversation` (global when nil, that chat's rules otherwise).
    private func scopedItems(conversation: Conversation?, modelContext: ModelContext) throws -> [RuleItem] {
        if let conversation {
            return conversation.rules
        }
        return try fetchItems(modelContext: modelContext)
    }

    nonisolated static func normalizeContent(_ content: String) -> String {
        content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private func findSimilar(_ items: [RuleItem], _ content: String) -> RuleItem? {
        let normalized = Self.normalizeContent(content)
        return items.first { Self.normalizeContent($0.content) == normalized }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/RulesStoreTests`
Expected: PASS — all `RulesStoreTests` tests, including the six above.

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Services/RulesStore.swift OpenChatTests/RulesStoreTests.swift
git commit -m "feat(rules): merge near-duplicate rules on save and update"
```

---

### Task 2: Rule vs. Memory classification instructions

**Files:**
- Modify: `OpenChat/Services/RulesStore.swift`
- Modify: `OpenChat/Services/MemoryStore.swift`
- Test: `OpenChatTests/RulesStoreTests.swift`
- Test: `OpenChatTests/MemoryStoreTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: rewritten `RulesStore.modelInstruction() -> String` and `MemoryStore.modelInstruction() -> String`. No signature changes — both remain `nonisolated static func modelInstruction() -> String`.

- [ ] **Step 1: Write the failing tests**

In `OpenChatTests/RulesStoreTests.swift`, replace the existing `testModelInstructionMentionsFenceAndScope` test:

```swift
    func testModelInstructionMentionsFenceAndScope() {
        let instruction = RulesStore.modelInstruction()
        XCTAssertTrue(instruction.contains("openchat-rule"))
        XCTAssertTrue(instruction.contains("scope"))
        XCTAssertTrue(instruction.contains("ask the user"))
    }

    func testModelInstructionDistinguishesRuleFromMemory() {
        let instruction = RulesStore.modelInstruction()
        XCTAssertTrue(instruction.contains("Memory"))
        XCTAssertTrue(instruction.contains("behave"))
    }

    func testModelInstructionWarnsAgainstRestatingOtherProposals() {
        let instruction = RulesStore.modelInstruction()
        XCTAssertTrue(instruction.contains("Skill"))
    }
```

In `OpenChatTests/MemoryStoreTests.swift`, add (inside the `MemoryStoreTests` class, after `testTemporarySkips`):

```swift
    func testModelInstructionDistinguishesMemoryFromRule() {
        let instruction = MemoryStore.modelInstruction()
        XCTAssertTrue(instruction.contains("openchat-memory"))
        XCTAssertTrue(instruction.contains("Rule"))
    }

    func testModelInstructionWarnsAgainstRestatingOtherProposals() {
        let instruction = MemoryStore.modelInstruction()
        XCTAssertTrue(instruction.contains("Skill"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/RulesStoreTests -only-testing:OpenChatTests/MemoryStoreTests`
Expected: FAIL — `testModelInstructionDistinguishesRuleFromMemory`, `testModelInstructionWarnsAgainstRestatingOtherProposals` (both classes) fail because the current instruction strings don't contain "Memory"/"Rule"/"Skill". `testModelInstructionMentionsFenceAndScope` still passes (unchanged assertions).

- [ ] **Step 3: Rewrite both `modelInstruction()` implementations**

In `OpenChat/Services/RulesStore.swift`, replace the existing `modelInstruction()` (lines 117-128):

```swift
    nonisolated static func modelInstruction() -> String {
        """
        The user enabled rule proposals in OpenChat. A Rule is an instruction about how you \
        should behave, act, or interact going forward — a standing behavior change, not a fact \
        about the user. Examples: "always answer in bullet points", "never use corporate \
        jargon", "write commit messages in the imperative mood". If what you want to save is \
        instead a fact about the user, their environment, or a situation worth recalling (e.g. \
        "I use Xcode 16", "my team ships on Thursdays"), propose a Memory instead, not a Rule. \
        If you're already proposing a Skill or another rule/memory for the same request, don't \
        also propose this unless it captures something genuinely separate — don't restate the \
        same intent across multiple proposals.

        Only propose a rule when you're genuinely confident it's a standing instruction — don't \
        propose speculative or one-off preferences.

        Propose it using:
        ```openchat-rule
        {"content":"...","scope":"global"|"chat"}
        ```
        Always include scope — if it's not clear from context whether this should apply to just \
        this chat or to every chat, ask the user before proposing it. Saved after confirmation \
        unless disabled.
        """
    }
```

In `OpenChat/Services/MemoryStore.swift`, replace the existing `modelInstruction()` (lines 135-137):

```swift
    nonisolated static func modelInstruction() -> String {
        """
        The user enabled long-term memory in OpenChat. A Memory is a durable fact about the \
        user, their environment, or a situation worth recalling — not an instruction about how \
        you should behave (that's a Rule instead). Examples: "I use Xcode 16", "my team ships \
        on Thursdays". If you're already proposing a Skill or another rule/memory for the same \
        request, don't also propose this unless it captures something genuinely separate — \
        don't restate the same intent across multiple proposals.

        Only propose a memory when you're genuinely confident it's a durable fact — don't \
        propose speculative or one-off details.

        Propose durable facts using:
        ```openchat-memory
        {"memories":["fact"]}
        ```
        or <memory_proposal>…</memory_proposal>. No secrets. Saved after confirmation unless \
        disabled.
        """
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/RulesStoreTests -only-testing:OpenChatTests/MemoryStoreTests`
Expected: PASS — all tests in both classes.

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Services/RulesStore.swift OpenChat/Services/MemoryStore.swift OpenChatTests/RulesStoreTests.swift OpenChatTests/MemoryStoreTests.swift
git commit -m "feat(rules,memory): add contrastive classification guidance to model instructions"
```

---

### Task 3: Existing-rules context injection

**Files:**
- Modify: `OpenChat/Services/RulesStore.swift`
- Modify: `OpenChat/Features/Chat/ChatViewModel.swift:619-632`
- Test: `OpenChatTests/RulesStoreTests.swift`

**Interfaces:**
- Consumes: `RuleItem.content: String` (existing), `RulesStore.fetchItems(modelContext:) -> [RuleItem]` (existing, global-only), `Conversation.rules: [RuleItem]` (existing).
- Produces: `static func contextSection(for items: [RuleItem]) -> String?` on `RulesStore` (same shape as `MemoryStore.contextSection(for:)`). `ChatViewModel`'s streaming setup now appends this section into `middleSections` inside the existing `if shouldAllowRuleProposals` block, before `RulesStore.modelInstruction()`.

- [ ] **Step 1: Write the failing test**

Add to `OpenChatTests/RulesStoreTests.swift` (after the Task 1/2 additions):

```swift
    func testContextSectionListsExistingRulesAndIsNilWhenEmpty() {
        XCTAssertNil(RulesStore.contextSection(for: []))

        let item = RuleItem(content: "Always answer in bullet points.")
        let section = RulesStore.contextSection(for: [item])

        XCTAssertNotNil(section)
        XCTAssertTrue(section!.contains("## Rules"))
        XCTAssertTrue(section!.contains("Always answer in bullet points."))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/RulesStoreTests/testContextSectionListsExistingRulesAndIsNilWhenEmpty`
Expected: FAIL to compile — `RulesStore.contextSection` doesn't exist yet.

- [ ] **Step 3: Implement `contextSection(for:)`**

In `OpenChat/Services/RulesStore.swift`, add this static method directly after `injectionText(from:)` (after line 111, before the helpers added in Task 1 — order among the three doesn't matter, keep them grouped together):

```swift
    /// Context block describing already-saved rules, injected so the model sees existing
    /// state before proposing a new one (mirrors `MemoryStore.contextSection(for:)`).
    static func contextSection(for items: [RuleItem]) -> String? {
        guard !items.isEmpty else { return nil }
        let body = items
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "- \($0)" }
            .joined(separator: "\n")
        guard !body.isEmpty else { return nil }
        return "## Rules\nStanding instructions already saved in OpenChat. Do not propose a new rule that duplicates or re-blends one already listed here.\n\n\(body)"
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/RulesStoreTests/testContextSectionListsExistingRulesAndIsNilWhenEmpty`
Expected: PASS

- [ ] **Step 5: Wire into `ChatViewModel`'s `middleSections`**

In `OpenChat/Features/Chat/ChatViewModel.swift`, replace lines 630-632:

```swift
                if shouldAllowRuleProposals {
                    middleSections.append(RulesStore.modelInstruction())
                }
```

with:

```swift
                if shouldAllowRuleProposals {
                    let globalRuleItems = (try? rulesStore.fetchItems(modelContext: modelContext)) ?? []
                    let existingRuleItems = globalRuleItems + conversation.rules
                    if let rulesSection = RulesStore.contextSection(for: existingRuleItems) {
                        middleSections.append(rulesSection)
                    }
                    middleSections.append(RulesStore.modelInstruction())
                }
```

This is a UI-integration change with no dedicated automated test (it lives inside a `Task` closure driven by live streaming) — verified manually per the Testing section at the end of this plan, consistent with this codebase's existing practice of flagging simulator-only checks (see the design spec's Testing section).

- [ ] **Step 6: Build to verify no compile errors**

Run: `xcodebuild build -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add OpenChat/Services/RulesStore.swift OpenChat/Features/Chat/ChatViewModel.swift OpenChatTests/RulesStoreTests.swift
git commit -m "feat(rules): inject existing-rules context so the model sees saved state before proposing"
```

---

### Task 4: Streaming fence-flash fix (open-fence stripping)

**Files:**
- Modify: `OpenChat/Services/RuleActionParser.swift`
- Modify: `OpenChat/Services/MemoryActionParser.swift`
- Test: `OpenChatTests/RuleActionParserTests.swift`
- Test: `OpenChatTests/MemoryActionParserTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `RuleActionParser.strippingFences(from:)` and `MemoryActionParser.strippingFences(from:)` (both existing `static func (String) -> String`) now also strip an unclosed opening fence/tag running to end-of-string, in addition to their existing closed-fence/tag behavior.

- [ ] **Step 1: Write the failing tests**

Add to `OpenChatTests/RuleActionParserTests.swift` (after `testStrippingFencesRemovesBothConventions`):

```swift
    func testStrippingFencesHidesUnclosedFenceMidStream() {
        let markdown = """
        Before
        ```openchat-rule
        {"content":"partial json still stream
        """
        let stripped = RuleActionParser.strippingFences(from: markdown)
        XCTAssertEqual(stripped, "Before")
    }

    func testStrippingFencesHidesUnclosedTagMidStream() {
        let markdown = """
        Before
        <rule_proposal>{"content":"partial json still stream
        """
        let stripped = RuleActionParser.strippingFences(from: markdown)
        XCTAssertEqual(stripped, "Before")
    }

    func testStrippingFencesLeavesPlainTextUnchanged() {
        let markdown = "Just a normal reply with no proposals."
        XCTAssertEqual(RuleActionParser.strippingFences(from: markdown), markdown)
    }
```

Add to `OpenChatTests/MemoryActionParserTests.swift` (read the file first to match its exact class name and existing style, then append inside the test class, following the same pattern used for `RuleActionParserTests` above):

```swift
    func testStrippingFencesHidesUnclosedFenceMidStream() {
        let markdown = """
        Before
        ```openchat-memory
        {"memories":["partial still stream
        """
        let stripped = MemoryActionParser.strippingFences(from: markdown)
        XCTAssertEqual(stripped, "Before")
    }

    func testStrippingFencesLeavesPlainTextUnchanged() {
        let markdown = "Just a normal reply with no proposals."
        XCTAssertEqual(MemoryActionParser.strippingFences(from: markdown), markdown)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/RuleActionParserTests -only-testing:OpenChatTests/MemoryActionParserTests`
Expected: FAIL — `testStrippingFencesHidesUnclosedFenceMidStream` and `testStrippingFencesHidesUnclosedTagMidStream` fail in both files: the current regexes require a closing fence/tag, so the raw `` ```openchat-rule\n{"content":"partial json still stream `` text passes through unstripped. `testStrippingFencesLeavesPlainTextUnchanged` passes already (no regression risk).

- [ ] **Step 3: Extend `RuleActionParser.strippingFences`**

In `OpenChat/Services/RuleActionParser.swift`, replace lines 4-21:

```swift
enum RuleActionParser {
    private static let fence = #"```openchat-rule\s*([\s\S]*?)```"#
    private static let tag = #"<rule_proposal>([\s\S]*?)</rule_proposal>"#
    private static let openFence = #"```openchat-rule[\s\S]*$"#
    private static let openTag = #"<rule_proposal>[\s\S]*$"#
    private static let fenceRegex = try? NSRegularExpression(pattern: fence)
    private static let tagRegex = try? NSRegularExpression(pattern: tag)
    private static let openFenceRegex = try? NSRegularExpression(pattern: openFence)
    private static let openTagRegex = try? NSRegularExpression(pattern: openTag)

    static func parse(_ markdown: String) -> [RuleProposal] {
        dedupe(parseBlocks(markdown, fenceRegex) + parseBlocks(markdown, tagRegex))
    }

    static func strippingFences(from markdown: String) -> String {
        var r = markdown
        for rx in [fenceRegex, tagRegex, openFenceRegex, openTagRegex] {
            guard let rx else { continue }
            r = rx.stringByReplacingMatches(in: r, range: NSRange(r.startIndex..<r.endIndex, in: r), withTemplate: "")
        }
        return r.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
```

Closed-fence/tag stripping runs first in the `for` loop, removing every complete block; any `` ```openchat-rule `` or `<rule_proposal>` token still present afterward is by definition unclosed, so the open-ended patterns then strip it through end-of-string.

- [ ] **Step 4: Extend `MemoryActionParser.strippingFences`**

In `OpenChat/Services/MemoryActionParser.swift`, replace lines 4-14:

```swift
enum MemoryActionParser {
    private static let fence = #"```openchat-memory\s*([\s\S]*?)```"#
    private static let tag = #"<memory_proposal>([\s\S]*?)</memory_proposal>"#
    private static let openFence = #"```openchat-memory[\s\S]*$"#
    private static let openTag = #"<memory_proposal>[\s\S]*$"#
    static func parse(_ markdown: String) -> [MemoryProposal] { dedupe(parseBlocks(markdown, fence) + parseBlocks(markdown, tag)) }
    static func strippingFences(from markdown: String) -> String {
        var r = markdown
        for p in [fence, tag] {
            guard let rx = try? NSRegularExpression(pattern: p) else { continue }
            r = rx.stringByReplacingMatches(in: r, range: NSRange(r.startIndex..<r.endIndex, in: r), withTemplate: "")
        }
        for p in [openFence, openTag] {
            guard let rx = try? NSRegularExpression(pattern: p) else { continue }
            r = rx.stringByReplacingMatches(in: r, range: NSRange(r.startIndex..<r.endIndex, in: r), withTemplate: "")
        }
        return r.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/RuleActionParserTests -only-testing:OpenChatTests/MemoryActionParserTests`
Expected: PASS — all tests in both files, including the new ones. Also re-run the full suite once here since these parsers are shared with `MessageBubbleView.displayContent`:

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: PASS — full suite green.

- [ ] **Step 6: Commit**

```bash
git add OpenChat/Services/RuleActionParser.swift OpenChat/Services/MemoryActionParser.swift OpenChatTests/RuleActionParserTests.swift OpenChatTests/MemoryActionParserTests.swift
git commit -m "fix(rules,memory): strip unclosed fences so streaming text never flashes raw proposal JSON"
```

---

## Manual Verification (follow-up, not automatable in this suite)

After all four tasks land, manually verify in the simulator, per the design spec's Testing section:
- Trigger a Rule proposal and a Memory proposal in the same chat; confirm no raw `` ```openchat-rule ``/`` ```openchat-memory `` text is visible at any point while the response streams in, with `requireConfirmation` both enabled and disabled.
- Propose two rules in the same chat where the second restates the first; confirm the second is either suppressed (near-duplicate merge) or, if genuinely distinct, saved as a separate rule — not a re-blended merge of both.

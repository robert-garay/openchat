# Document Upload/Paste Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users attach PDF documents to chat messages (Files picker, paste, drag & drop) for models that can process files, mirroring the existing image-attachment feature end-to-end.

**Architecture:** Add a `ChatDocumentAttachment` model paralleling `ChatImageAttachment`, thread it through `ChatMessage`/`ChatTurn`/`ChatRequestHistory`/`ConversationCompactionService`/`MultimodalRequestEncoder` (renaming `AnthropicPart.ImageSource` to a shared `Base64Source`), then wire the composer (`MessageComposerView`, `ComposerTextView`) and message bubble (`MessageBubbleView`) UI, plus a new QuickLook-based `DocumentPreviewView`.

**Tech Stack:** Swift/SwiftUI, SwiftData, XCTest (`@testable import OpenChat`), QuickLook (`QLPreviewController`).

## Global Constraints

- PDF only (`application/pdf`), matching the approved spec scope.
- Attach methods: Files picker (`.fileImporter`), paste (menu button + in-field ⌘V via `ComposerTextView`), and drag & drop.
- Max size 32MB (`32 * 1024 * 1024`) — shared Anthropic/OpenAI PDF cap.
- Validate PDFs by magic-byte header `[0x25, 0x50, 0x44, 0x46]` ("%PDF") in addition to size.
- Wire formats: Anthropic `{"type": "document", "source": {"type": "base64", "media_type": "application/pdf", "data": ...}}`; OpenAI-compatible `{"type": "file", "file": {"filename": ..., "file_data": "data:application/pdf;base64,..."}}`.
- Part ordering in multimodal requests: documents, then images, then text.
- Test framework: XCTest (`import XCTest`, `@testable import OpenChat`) — this codebase's established convention (confirmed across all existing test files), not Swift Testing.
- No `ChatViewModel`/UI unit tests — this app has no existing unit test coverage for `MessageBubbleView` or `ChatViewModel`'s streaming paths (confirmed precedent: `docs/superpowers/specs/2026-08-05-image-output-actions-design.md`). Those tasks are implementation-only, verified manually.
- `ModelCapability.files` already exists (`OpenChat/Models/ModelCapability.swift:14,30,44,57,91`) and is already inferred from provider catalog responses — no changes needed there.

---

### Task 1: `ChatDocumentAttachment` model + encoder

**Files:**
- Create: `OpenChat/Models/ChatDocumentAttachment.swift`
- Create: `OpenChatTests/DocumentAttachmentTests.swift`

**Interfaces:**
- Consumes: nothing (leaf model, mirrors `OpenChat/Models/ChatImageAttachment.swift`).
- Produces: `struct ChatDocumentAttachment: Identifiable, Hashable, Sendable, Codable` with `id: UUID`, `filename: String`, `mimeType: String`, `data: Data`, computed `dataURI: String`, and `init(id: UUID = UUID(), filename: String, mimeType: String, data: Data)`. `enum DocumentAttachmentEncoder` with `static let maxByteCount = 32 * 1024 * 1024` and `static func makeAttachment(from data: Data, filename: String) -> ChatDocumentAttachment?`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import OpenChat

final class DocumentAttachmentTests: XCTestCase {
    private let pdfHeader = Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]) // "%PDF-1.4"

    func testChatDocumentAttachmentRoundTrip() throws {
        let original = ChatDocumentAttachment(filename: "report.pdf", mimeType: "application/pdf", data: pdfHeader)
        let encoded = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([ChatDocumentAttachment].self, from: encoded)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].filename, "report.pdf")
        XCTAssertEqual(decoded[0].mimeType, "application/pdf")
        XCTAssertEqual(decoded[0].data, original.data)
        XCTAssertTrue(decoded[0].dataURI.hasPrefix("data:application/pdf;base64,"))
    }

    func testDocumentAttachmentEncoderAcceptsValidPDF() {
        let attachment = DocumentAttachmentEncoder.makeAttachment(from: pdfHeader, filename: "notes.pdf")
        XCTAssertNotNil(attachment)
        XCTAssertEqual(attachment?.filename, "notes.pdf")
        XCTAssertEqual(attachment?.mimeType, "application/pdf")
        XCTAssertEqual(attachment?.data, pdfHeader)
    }

    func testDocumentAttachmentEncoderRejectsNonPDF() {
        let notPDF = Data([0x50, 0x4B, 0x03, 0x04]) // ZIP magic bytes
        XCTAssertNil(DocumentAttachmentEncoder.makeAttachment(from: notPDF, filename: "fake.pdf"))
    }

    func testDocumentAttachmentEncoderRejectsOversized() {
        var oversized = Data([0x25, 0x50, 0x44, 0x46])
        oversized.append(Data(count: DocumentAttachmentEncoder.maxByteCount))
        XCTAssertNil(DocumentAttachmentEncoder.makeAttachment(from: oversized, filename: "huge.pdf"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/DocumentAttachmentTests`
Expected: FAIL — `ChatDocumentAttachment` / `DocumentAttachmentEncoder` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// A PDF document on a chat turn — user-uploaded, for models that can read files.
struct ChatDocumentAttachment: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var filename: String
    var mimeType: String
    var data: Data

    init(id: UUID = UUID(), filename: String, mimeType: String, data: Data) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }

    var dataURI: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}

enum DocumentAttachmentEncoder {
    /// Anthropic & OpenAI PDF cap.
    static let maxByteCount = 32 * 1024 * 1024

    private static let pdfMagicBytes: [UInt8] = [0x25, 0x50, 0x44, 0x46] // "%PDF"

    static func makeAttachment(from data: Data, filename: String) -> ChatDocumentAttachment? {
        guard data.count <= maxByteCount, data.starts(with: pdfMagicBytes) else { return nil }
        return ChatDocumentAttachment(filename: filename, mimeType: "application/pdf", data: data)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/DocumentAttachmentTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Models/ChatDocumentAttachment.swift OpenChatTests/DocumentAttachmentTests.swift
git commit -m "feat: add ChatDocumentAttachment model and encoder"
```

---

### Task 2: `ChatMessage.documentAttachments`

**Files:**
- Modify: `OpenChat/Models/ChatMessage.swift`
- Test: `OpenChatTests/DocumentAttachmentTests.swift`

**Interfaces:**
- Consumes: `ChatDocumentAttachment` (Task 1).
- Produces: `ChatMessage.documentAttachmentsData: Data?`, computed `documentAttachments: [ChatDocumentAttachment]` (get/set, same JSON pattern as `imageAttachments`), new `init(...)` param `documentAttachments: [ChatDocumentAttachment] = []`.

- [ ] **Step 1: Write the failing test**

Append to `OpenChatTests/DocumentAttachmentTests.swift`:

```swift
    func testChatMessageStoresDocumentAttachments() {
        let document = ChatDocumentAttachment(filename: "spec.pdf", mimeType: "application/pdf", data: pdfHeader)
        let message = ChatMessage(role: .user, content: "review this", documentAttachments: [document])
        XCTAssertEqual(message.documentAttachments.count, 1)
        XCTAssertEqual(message.documentAttachments[0].filename, "spec.pdf")
        message.documentAttachments = []
        XCTAssertNil(message.documentAttachmentsData)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/DocumentAttachmentTests/testChatMessageStoresDocumentAttachments`
Expected: FAIL — no `documentAttachments` member / no matching initializer.

- [ ] **Step 3: Write minimal implementation**

In `OpenChat/Models/ChatMessage.swift`, add a new stored property after line 25 (`var attachmentsData: Data?`):

```swift
    /// JSON-encoded `[ChatDocumentAttachment]` for PDF-bearing user turns.
    var documentAttachmentsData: Data?
```

Add a computed property after `imageAttachments` (after line 45, before `init`):

```swift
    var documentAttachments: [ChatDocumentAttachment] {
        get {
            guard let documentAttachmentsData else { return [] }
            return (try? JSONDecoder().decode([ChatDocumentAttachment].self, from: documentAttachmentsData)) ?? []
        }
        set {
            if newValue.isEmpty {
                documentAttachmentsData = nil
            } else {
                documentAttachmentsData = try? JSONEncoder().encode(newValue)
            }
        }
    }
```

Update the `init` signature (lines 47-71) to add the new parameter and assignment:

```swift
    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = .now,
        isStreaming: Bool = false,
        errorMessage: String? = nil,
        providerID: String? = nil,
        modelID: String? = nil,
        imageAttachments: [ChatImageAttachment] = [],
        documentAttachments: [ChatDocumentAttachment] = []
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.errorMessage = errorMessage
        self.providerID = providerID
        self.modelID = modelID
        if imageAttachments.isEmpty {
            self.attachmentsData = nil
        } else {
            self.attachmentsData = try? JSONEncoder().encode(imageAttachments)
        }
        if documentAttachments.isEmpty {
            self.documentAttachmentsData = nil
        } else {
            self.documentAttachmentsData = try? JSONEncoder().encode(documentAttachments)
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/DocumentAttachmentTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Models/ChatMessage.swift OpenChatTests/DocumentAttachmentTests.swift
git commit -m "feat: add documentAttachments to ChatMessage"
```

---

### Task 3: `ChatTurn.documents` + `ChatServiceError.modelLacksFiles`

**Files:**
- Modify: `OpenChat/Services/ChatTurn.swift`
- Test: `OpenChatTests/DocumentAttachmentTests.swift`

**Interfaces:**
- Consumes: `ChatDocumentAttachment` (Task 1).
- Produces: `ChatTurn.documents: [ChatDocumentAttachment]` (init param, default `[]`), `ChatTurn.hasDocuments: Bool`, `ChatServiceError.modelLacksFiles` case with `errorDescription` "This model can't process documents. Choose a model marked with a doc icon."

- [ ] **Step 1: Write the failing test**

Append to `OpenChatTests/DocumentAttachmentTests.swift`:

```swift
    func testChatTurnHasDocuments() {
        let document = ChatDocumentAttachment(filename: "a.pdf", mimeType: "application/pdf", data: pdfHeader)
        let turn = ChatTurn(role: .user, content: "check", documents: [document])
        XCTAssertTrue(turn.hasDocuments)
        XCTAssertFalse(ChatTurn(role: .user, content: "hi").hasDocuments)
    }

    func testFilesCapabilityErrorMessage() {
        let message = ChatServiceError.modelLacksFiles.errorDescription
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.localizedCaseInsensitiveContains("document") == true)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/DocumentAttachmentTests`
Expected: FAIL — no `documents` init param / no `hasDocuments` / no `.modelLacksFiles` case.

- [ ] **Step 3: Write minimal implementation**

Replace `OpenChat/Services/ChatTurn.swift` lines 1-30 (the `ChatTurn` struct) with:

```swift
import Foundation

/// A provider-agnostic representation of one turn in the conversation,
/// built from `ChatMessage` right before it's sent over the network.
struct ChatTurn: Sendable {
    var role: MessageRole
    var content: String
    var images: [ChatImageAttachment]
    var documents: [ChatDocumentAttachment]
    /// Assistant turns may request tool calls instead of (or alongside) text.
    var toolCalls: [ChatToolCall]
    /// For `.tool` turns (OpenAI) / tool_result blocks (Anthropic).
    var toolCallID: String?

    init(
        role: MessageRole,
        content: String,
        images: [ChatImageAttachment] = [],
        documents: [ChatDocumentAttachment] = [],
        toolCalls: [ChatToolCall] = [],
        toolCallID: String? = nil
    ) {
        self.role = role
        self.content = content
        self.images = images
        self.documents = documents
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    var hasImages: Bool { !images.isEmpty }
    var hasDocuments: Bool { !documents.isEmpty }
    var hasToolCalls: Bool { !toolCalls.isEmpty }
}
```

Then add the new error case to `ChatServiceError` (after `case modelLacksVision` at line 39, and after its `errorDescription` branch at lines 63-64):

```swift
    case modelLacksVision
    case modelLacksFiles
```

```swift
        case .modelLacksVision:
            return "This model can't process images. Choose a vision-capable model."
        case .modelLacksFiles:
            return "This model can't process documents. Choose a model marked with a doc icon."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/DocumentAttachmentTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Services/ChatTurn.swift OpenChatTests/DocumentAttachmentTests.swift
git commit -m "feat: add ChatTurn.documents and modelLacksFiles error"
```

---

### Task 4: `AIModel.supportsFiles`

**Files:**
- Modify: `OpenChat/Models/AIModel.swift`
- Test: `OpenChatTests/DocumentAttachmentTests.swift`

**Interfaces:**
- Consumes: `ModelCapability.files` (already exists, `OpenChat/Models/ModelCapability.swift:14`).
- Produces: `AIModel.supportsFiles: Bool`.

- [ ] **Step 1: Write the failing test**

Append to `OpenChatTests/DocumentAttachmentTests.swift`:

```swift
    func testAIModelSupportsFiles() {
        let withFiles = AIModel(id: "m1", displayName: "M1", capabilities: [.files])
        let withoutFiles = AIModel(id: "m2", displayName: "M2", capabilities: [.vision])
        XCTAssertTrue(withFiles.supportsFiles)
        XCTAssertFalse(withoutFiles.supportsFiles)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/DocumentAttachmentTests/testAIModelSupportsFiles`
Expected: FAIL — no `supportsFiles` member.

- [ ] **Step 3: Write minimal implementation**

In `OpenChat/Models/AIModel.swift`, add after `supportsTools` (line 20-22):

```swift
    var supportsTools: Bool {
        capabilities.contains(.tools)
    }

    var supportsFiles: Bool {
        capabilities.contains(.files)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/DocumentAttachmentTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Models/AIModel.swift OpenChatTests/DocumentAttachmentTests.swift
git commit -m "feat: add AIModel.supportsFiles"
```

---

### Task 5: `MultimodalRequestEncoder` document parts

**Files:**
- Modify: `OpenChat/Services/MultimodalRequestEncoder.swift`
- Test: `OpenChatTests/DocumentAttachmentTests.swift`

**Interfaces:**
- Consumes: `ChatTurn.documents`/`hasDocuments` (Task 3), `ChatDocumentAttachment.dataURI`/`mimeType`/`data`/`filename` (Task 1).
- Produces: `MultimodalRequestEncoder.Base64Source` (renamed from `AnthropicPart.ImageSource`, now top-level), `MultimodalRequestEncoder.OpenAIPart.FileData`, `MultimodalRequestEncoder.OpenAIPart.file: FileData?`, `MultimodalRequestEncoder.AnthropicPart.source: Base64Source?` (unchanged field name, renamed type). `openAIParts(for:)` / `anthropicParts(for:)` guard on `hasImages || hasDocuments` and order parts documents → images → text.

- [ ] **Step 1: Write the failing tests**

Append to `OpenChatTests/DocumentAttachmentTests.swift`:

```swift
    func testOpenAIMultimodalPartsIncludeDocumentOnly() throws {
        let document = ChatDocumentAttachment(filename: "spec.pdf", mimeType: "application/pdf", data: pdfHeader)
        let turn = ChatTurn(role: .user, content: "Summarize this", documents: [document])
        let parts = MultimodalRequestEncoder.openAIParts(for: turn)
        XCTAssertEqual(parts?.count, 2)
        XCTAssertEqual(parts?[0].type, "file")
        XCTAssertEqual(parts?[0].file?.filename, "spec.pdf")
        XCTAssertEqual(parts?[0].file?.fileData, document.dataURI)
        XCTAssertEqual(parts?[1].type, "text")
        XCTAssertEqual(parts?[1].text, "Summarize this")
    }

    func testAnthropicMultimodalPartsIncludeDocumentOnly() {
        let document = ChatDocumentAttachment(filename: "spec.pdf", mimeType: "application/pdf", data: pdfHeader)
        let turn = ChatTurn(role: .user, content: "Summarize this", documents: [document])
        let parts = MultimodalRequestEncoder.anthropicParts(for: turn)
        XCTAssertEqual(parts?.count, 2)
        XCTAssertEqual(parts?[0].type, "document")
        XCTAssertEqual(parts?[0].source?.mediaType, "application/pdf")
        XCTAssertEqual(parts?[0].source?.data, document.data.base64EncodedString())
        XCTAssertEqual(parts?[1].type, "text")
        XCTAssertEqual(parts?[1].text, "Summarize this")
    }

    func testMultimodalPartsOrderDocumentsBeforeImagesBeforeText() {
        let document = ChatDocumentAttachment(filename: "spec.pdf", mimeType: "application/pdf", data: pdfHeader)
        let image = ChatImageAttachment(mimeType: "image/png", data: Data([1, 2, 3]))
        let turn = ChatTurn(role: .user, content: "Both", images: [image], documents: [document])

        let openAIParts = MultimodalRequestEncoder.openAIParts(for: turn)
        XCTAssertEqual(openAIParts?.map(\.type), ["file", "image_url", "text"])

        let anthropicParts = MultimodalRequestEncoder.anthropicParts(for: turn)
        XCTAssertEqual(anthropicParts?.map(\.type), ["document", "image", "text"])
    }

    func testMultimodalPartsForDocumentOnlyTurnAreNotNil() {
        let document = ChatDocumentAttachment(filename: "a.pdf", mimeType: "application/pdf", data: pdfHeader)
        let turn = ChatTurn(role: .user, content: "", documents: [document])
        XCTAssertNotNil(MultimodalRequestEncoder.openAIParts(for: turn))
        XCTAssertNotNil(MultimodalRequestEncoder.anthropicParts(for: turn))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/DocumentAttachmentTests`
Expected: FAIL — no `file`/`FileData` on `OpenAIPart`, no `document` branch, `Base64Source` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

Replace the entire contents of `OpenChat/Services/MultimodalRequestEncoder.swift`:

```swift
import Foundation

/// Shared multimodal request shaping for OpenAI-compatible and Anthropic wire formats.
enum MultimodalRequestEncoder {
    struct Base64Source: Encodable, Equatable {
        var type = "base64"
        var mediaType: String
        var data: String

        enum CodingKeys: String, CodingKey {
            case type, data
            case mediaType = "media_type"
        }
    }

    struct OpenAIPart: Encodable, Equatable {
        var type: String
        var text: String?
        var imageURL: ImageURL?
        var file: FileData?

        enum CodingKeys: String, CodingKey {
            case type, text, file
            case imageURL = "image_url"
        }

        struct ImageURL: Encodable, Equatable {
            var url: String
        }

        struct FileData: Encodable, Equatable {
            var filename: String
            var fileData: String

            enum CodingKeys: String, CodingKey {
                case filename
                case fileData = "file_data"
            }
        }
    }

    struct AnthropicPart: Encodable, Equatable {
        var type: String
        var text: String?
        var source: Base64Source?
    }

    static func openAIParts(for turn: ChatTurn) -> [OpenAIPart]? {
        guard turn.hasImages || turn.hasDocuments else { return nil }
        var parts: [OpenAIPart] = turn.documents.map {
            OpenAIPart(type: "file", text: nil, imageURL: nil, file: .init(filename: $0.filename, fileData: $0.dataURI))
        }
        parts.append(contentsOf: turn.images.map {
            OpenAIPart(type: "image_url", text: nil, imageURL: .init(url: $0.dataURI), file: nil)
        })
        let trimmed = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(OpenAIPart(type: "text", text: trimmed, imageURL: nil, file: nil))
        }
        return parts
    }

    static func anthropicParts(for turn: ChatTurn) -> [AnthropicPart]? {
        guard turn.hasImages || turn.hasDocuments else { return nil }
        var parts: [AnthropicPart] = turn.documents.map {
            AnthropicPart(
                type: "document",
                text: nil,
                source: .init(mediaType: $0.mimeType, data: $0.data.base64EncodedString())
            )
        }
        parts.append(contentsOf: turn.images.map {
            AnthropicPart(
                type: "image",
                text: nil,
                source: .init(mediaType: $0.mimeType, data: $0.data.base64EncodedString())
            )
        })
        let trimmed = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(AnthropicPart(type: "text", text: trimmed, source: nil))
        } else if parts.isEmpty {
            parts.append(AnthropicPart(type: "text", text: "", source: nil))
        }
        return parts
    }
}
```

Note: this preserves `OpenChatTests/MultimodalAttachmentTests.swift`'s existing assertions unchanged (`parts?[0].source?.mediaType`, `parts?[0].type == "image"`, etc.) since `Base64Source` keeps the exact same field names as the old `ImageSource`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/DocumentAttachmentTests -only-testing:OpenChatTests/MultimodalAttachmentTests`
Expected: PASS (both test files — confirms the rename didn't break existing image tests)

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Services/MultimodalRequestEncoder.swift OpenChatTests/DocumentAttachmentTests.swift
git commit -m "feat: encode document parts in MultimodalRequestEncoder"
```

---

### Task 6: `ChatRequestHistory.includeDocuments`

**Files:**
- Modify: `OpenChat/Services/ChatRequestHistory.swift`
- Modify: `OpenChatTests/ChatRequestHistoryTests.swift`

**Interfaces:**
- Consumes: `ChatMessage.documentAttachments` (Task 2), `ChatTurn(documents:)` (Task 3).
- Produces: `ChatRequestHistory.omittedDocumentPlaceholder: String`, `ChatRequestHistory.turns(from:includeImages:includeDocuments:excludingMessageID:)`.

- [ ] **Step 1: Write the failing tests**

Append to `OpenChatTests/ChatRequestHistoryTests.swift`, before the final closing `}`:

```swift
    func testIncludeDocumentsKeepsAttachments() {
        let document = ChatDocumentAttachment(filename: "a.pdf", mimeType: "application/pdf", data: Data([1, 2, 3]))
        let message = ChatMessage(role: .user, content: "What is this?", documentAttachments: [document])

        let turns = ChatRequestHistory.turns(from: [message], includeImages: true, includeDocuments: true)

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].content, "What is this?")
        XCTAssertEqual(turns[0].documents.count, 1)
        XCTAssertEqual(turns[0].documents[0].data, Data([1, 2, 3]))
    }

    func testOmitDocumentsKeepsTextAndAddsPlaceholder() {
        let document = ChatDocumentAttachment(filename: "a.pdf", mimeType: "application/pdf", data: Data([1, 2, 3]))
        let message = ChatMessage(role: .user, content: "What is this?", documentAttachments: [document])

        let turns = ChatRequestHistory.turns(from: [message], includeImages: true, includeDocuments: false)

        XCTAssertEqual(turns.count, 1)
        XCTAssertTrue(turns[0].documents.isEmpty)
        XCTAssertTrue(turns[0].content.contains("What is this?"))
        XCTAssertTrue(turns[0].content.contains(ChatRequestHistory.omittedDocumentPlaceholder))
    }

    func testOmitDocumentsReplacesDocumentOnlyTurnWithPlaceholder() {
        let document = ChatDocumentAttachment(filename: "a.pdf", mimeType: "application/pdf", data: Data([9]))
        let message = ChatMessage(role: .user, content: "", documentAttachments: [document])

        let turns = ChatRequestHistory.turns(from: [message], includeImages: true, includeDocuments: false)

        XCTAssertEqual(turns.count, 1)
        XCTAssertTrue(turns[0].documents.isEmpty)
        XCTAssertEqual(turns[0].content, ChatRequestHistory.omittedDocumentPlaceholder)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/ChatRequestHistoryTests`
Expected: FAIL — `turns(from:includeImages:includeDocuments:excludingMessageID:)` doesn't exist; existing calls at lines 9/21/33/44-45/56-59 also break (missing param) until Step 3 adds the default.

- [ ] **Step 3: Write minimal implementation**

Replace the entire contents of `OpenChat/Services/ChatRequestHistory.swift`:

```swift
import Foundation

/// Builds provider-bound chat turns from persisted messages.
/// Images and documents stay on `ChatMessage`; callers choose whether to include them in the outbound payload.
enum ChatRequestHistory {
    static let omittedImagePlaceholder = "[Image omitted — this model can’t process images]"
    static let omittedDocumentPlaceholder = "[Document omitted — this model can't process documents]"

    static func turns(
        from messages: [ChatMessage],
        includeImages: Bool,
        includeDocuments: Bool = true,
        excludingMessageID: UUID? = nil
    ) -> [ChatTurn] {
        messages.compactMap { message in
            if let excludingMessageID, message.id == excludingMessageID { return nil }

            let storedImages = message.imageAttachments
            let images = includeImages ? storedImages : []
            let storedDocuments = message.documentAttachments
            let documents = includeDocuments ? storedDocuments : []
            var content = message.content

            var omittedNotes: [String] = []
            if !includeImages, !storedImages.isEmpty {
                omittedNotes.append(omittedImagePlaceholder)
            }
            if !includeDocuments, !storedDocuments.isEmpty {
                omittedNotes.append(omittedDocumentPlaceholder)
            }
            if !omittedNotes.isEmpty {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                let notes = omittedNotes.joined(separator: "\n")
                content = trimmed.isEmpty ? notes : trimmed + "\n\n" + notes
            }

            guard !content.isEmpty || !images.isEmpty || !documents.isEmpty else { return nil }
            return ChatTurn(role: message.role, content: content, images: images, documents: documents)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/ChatRequestHistoryTests`
Expected: PASS (all 8 tests — 5 existing image tests unchanged plus 3 new document tests)

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Services/ChatRequestHistory.swift OpenChatTests/ChatRequestHistoryTests.swift
git commit -m "feat: add includeDocuments support to ChatRequestHistory"
```

---

### Task 7: `ConversationCompactionService` document eligibility + threading

**Files:**
- Modify: `OpenChat/Services/ConversationCompactionService.swift`
- Modify: `OpenChatTests/ConversationCompactionTests.swift`

**Interfaces:**
- Consumes: `ChatMessage.documentAttachments` (Task 2), `ChatRequestHistory.turns(from:includeImages:includeDocuments:excludingMessageID:)` (Task 6).
- Produces: `ConversationCompactionService.apiHistoryTurns(sortedMessages:compactedSummary:compactedThroughMessageID:includeImages:includeDocuments:excludingMessageID:)`. Eligibility filter (used internally by `apiHistoryTurns`) now also counts messages with only document attachments.

- [ ] **Step 1: Write the failing test**

Append to `OpenChatTests/ConversationCompactionTests.swift`, before the final closing `}`:

```swift
    func testAPIHistoryTurnsOmitsCompactedDocumentBinariesWhenExcluded() {
        let document = ChatDocumentAttachment(filename: "report.pdf", mimeType: "application/pdf", data: Data([0x25, 0x50, 0x44, 0x46]))
        let old = ChatMessage(role: .user, content: "Doc", documentAttachments: [document])
        let recent = ChatMessage(role: .user, content: "Follow up")

        let turns = ConversationCompactionService.apiHistoryTurns(
            sortedMessages: [old, recent],
            compactedSummary: "User shared a document.",
            compactedThroughMessageID: old.id
        )

        XCTAssertEqual(turns.count, 2)
        XCTAssertTrue(turns[0].content.contains("Compacted conversation context"))
        XCTAssertEqual(turns[1].content, "Follow up")
        XCTAssertTrue(turns[1].documents.isEmpty)
    }

    func testAPIHistoryTurnsDocumentOnlyMessageEligibleForCompaction() {
        let document = ChatDocumentAttachment(filename: "report.pdf", mimeType: "application/pdf", data: Data([0x25, 0x50, 0x44, 0x46]))
        let documentOnly = ChatMessage(role: .user, content: "", documentAttachments: [document])
        let turns = ConversationCompactionService.apiHistoryTurns(
            sortedMessages: [documentOnly],
            compactedSummary: nil,
            compactedThroughMessageID: nil
        )
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].documents.count, 1)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/ConversationCompactionTests`
Expected: FAIL — `testAPIHistoryTurnsDocumentOnlyMessageEligibleForCompaction` fails because the eligibility filter drops document-only messages (empty content, zero images).

- [ ] **Step 3: Write minimal implementation**

In `OpenChat/Services/ConversationCompactionService.swift`, update `apiHistoryTurns` (lines 136-180):

```swift
    /// Builds chat turns for API requests, injecting compact summary before post-watermark messages.
    static func apiHistoryTurns(
        sortedMessages: [ChatMessage],
        compactedSummary: String?,
        compactedThroughMessageID: UUID?,
        includeImages: Bool = true,
        includeDocuments: Bool = true,
        excludingMessageID: UUID? = nil
    ) -> [ChatTurn] {
        let eligible = sortedMessages.filter {
            $0.id != excludingMessageID
                && (!$0.content.isEmpty || !$0.imageAttachments.isEmpty || !$0.documentAttachments.isEmpty)
                && !($0.role == .assistant && $0.isStreaming)
        }

        let summary = compactedSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasSummary = !summary.isEmpty

        let postWatermarkMessages: [ChatMessage]
        if hasSummary, let watermarkID = compactedThroughMessageID,
           let watermarkIndex = eligible.firstIndex(where: { $0.id == watermarkID }) {
            postWatermarkMessages = Array(eligible[(watermarkIndex + 1)...])
        } else if hasSummary {
            postWatermarkMessages = []
        } else {
            postWatermarkMessages = eligible
        }

        var turns: [ChatTurn] = []
        if hasSummary {
            turns.append(
                ChatTurn(
                    role: .user,
                    content: "[Compacted conversation context]\n\n\(summary)"
                )
            )
        }

        turns.append(
            contentsOf: ChatRequestHistory.turns(
                from: postWatermarkMessages,
                includeImages: includeImages,
                includeDocuments: includeDocuments
            )
        )

        return turns
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/ConversationCompactionTests`
Expected: PASS (all tests, including the pre-existing 9)

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Services/ConversationCompactionService.swift OpenChatTests/ConversationCompactionTests.swift
git commit -m "feat: thread includeDocuments through ConversationCompactionService"
```

---

### Task 8: `ChatViewModel` document attachment plumbing

**Files:**
- Modify: `OpenChat/Features/Chat/ChatViewModel.swift`

**Interfaces:**
- Consumes: `ChatDocumentAttachment` (Task 1), `ChatMessage(documentAttachments:)` (Task 2), `AIModel.supportsFiles` (Task 4), `ChatServiceError.modelLacksFiles` (Task 3), `ConversationCompactionService.apiHistoryTurns(...includeDocuments:...)` (Task 7).
- Produces: `ChatViewModel.pendingDocumentAttachments: [ChatDocumentAttachment]`, `ChatViewModel.supportsFiles: Bool`, extended `PendingModelSwitch` (adds `omitsThreadDocuments: Bool`, `clearsPendingAttachments` now also considers pending documents), `selectModel`/`confirmPendingModelSwitch`/`applyModelSelection`/`send`/`saveEdit`/`requestAssistantReply` updated for documents. No test file — implementation-only per Global Constraints (no `ChatViewModel` unit test coverage in this codebase).

- [ ] **Step 1: Add `pendingDocumentAttachments` and `supportsFiles`**

In `OpenChat/Features/Chat/ChatViewModel.swift`, add a new property after line 10 (`var pendingAttachments: [ChatImageAttachment] = []`):

```swift
    var pendingAttachments: [ChatImageAttachment] = []
    var pendingDocumentAttachments: [ChatDocumentAttachment] = []
```

Add `supportsFiles` after `supportsVision` (lines 150-152):

```swift
    var supportsVision: Bool {
        currentModel?.supportsVision ?? false
    }

    var supportsFiles: Bool {
        currentModel?.supportsFiles ?? false
    }
```

- [ ] **Step 2: Extend `PendingModelSwitch`**

Replace the `PendingModelSwitch` struct (lines 25-44):

```swift
    struct PendingModelSwitch: Equatable {
        var providerID: String
        var modelID: String
        var modelDisplayName: String
        var clearsPendingAttachments: Bool
        var omitsThreadImages: Bool
        var omitsThreadDocuments: Bool

        var message: String {
            var parts: [String] = []
            if omitsThreadImages {
                parts.append(
                    "\(modelDisplayName) can’t process images. Photos already in this chat stay visible but won’t be sent until you switch back to a vision model."
                )
            }
            if omitsThreadDocuments {
                parts.append(
                    "\(modelDisplayName) can't process documents. Documents already in this chat stay visible but won't be sent until you switch back to a file-capable model."
                )
            }
            if clearsPendingAttachments {
                parts.append("Unsent attachments will be removed.")
            }
            return parts.joined(separator: "\n\n")
        }
    }
```

- [ ] **Step 3: Update `selectModel`**

Replace `selectModel` (lines 154-179):

```swift
    func selectModel(providerID: String, modelID: String) {
        if providerID == conversation.providerID, modelID == conversation.modelID {
            return
        }

        let model = providerStore.model(providerID: providerID, modelID: modelID)
        let targetSupportsVision = model?.supportsVision == true
        let targetSupportsFiles = model?.supportsFiles == true
        let hasThreadImages = conversation.messages.contains { !$0.imageAttachments.isEmpty }
        let hasThreadDocuments = conversation.messages.contains { !$0.documentAttachments.isEmpty }
        let clearsPendingAttachments = (!pendingAttachments.isEmpty && !targetSupportsVision)
            || (!pendingDocumentAttachments.isEmpty && !targetSupportsFiles)
        let leavingVision = currentModel?.supportsVision == true
        let leavingFiles = currentModel?.supportsFiles == true

        let omitsThreadImages = !targetSupportsVision && hasThreadImages && leavingVision
        let omitsThreadDocuments = !targetSupportsFiles && hasThreadDocuments && leavingFiles

        let needsConfirmation = omitsThreadImages || omitsThreadDocuments || clearsPendingAttachments
        if needsConfirmation {
            pendingModelSwitch = PendingModelSwitch(
                providerID: providerID,
                modelID: modelID,
                modelDisplayName: model?.displayName ?? "This model",
                clearsPendingAttachments: clearsPendingAttachments,
                omitsThreadImages: omitsThreadImages,
                omitsThreadDocuments: omitsThreadDocuments
            )
            return
        }

        applyModelSelection(providerID: providerID, modelID: modelID, clearPendingAttachments: clearsPendingAttachments)
    }
```

- [ ] **Step 4: Update `applyModelSelection`**

Replace `applyModelSelection` (lines 283-291):

```swift
    private func applyModelSelection(providerID: String, modelID: String, clearPendingAttachments: Bool) {
        conversation.providerID = providerID
        conversation.modelID = modelID
        conversation.updatedAt = .now
        providerStore.recordModelUsage(providerID: providerID, modelID: modelID)
        if clearPendingAttachments {
            pendingAttachments = []
            pendingDocumentAttachments = []
        }
    }
```

- [ ] **Step 5: Update `send()`**

Replace `send()` (lines 351-395):

```swift
    func send() {
        let rawText = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingAttachments
        let documents = pendingDocumentAttachments
        guard (!rawText.isEmpty || !images.isEmpty || !documents.isEmpty), !isStreaming else { return }

        if !images.isEmpty, !supportsVision {
            capabilityWarning = ChatServiceError.modelLacksVision.errorDescription
            return
        }
        if !documents.isEmpty, !supportsFiles {
            capabilityWarning = ChatServiceError.modelLacksFiles.errorDescription
            return
        }

        let skills = fetchSkillMatches()
        let resolution = SkillResolver.resolve(text: rawText, skills: skills)
        let text = resolution?.storedMessage ?? rawText
        guard !text.isEmpty || !images.isEmpty || !documents.isEmpty else { return }

        composerText = ""
        pendingAttachments = []
        pendingDocumentAttachments = []

        // Explicit /slash-name invocation pins its instructions into the conversation
        // immediately, synchronously, before the user's message — same-turn, same as
        // an auto-invoked skill lands next-turn once persisted by requestAssistantReply().
        if let resolution {
            insertSkillSystemMessage(for: resolution.skill)
        }

        let userMessage = ChatMessage(role: .user, content: text, imageAttachments: images, documentAttachments: documents)
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)
        modelContext.insert(userMessage)

        let isFirstUserMessage = conversation.messages.filter { $0.role == .user }.count == 1
        if isFirstUserMessage, !conversation.isTemporary, !conversation.hasCustomTitle {
            let provisional = ConversationTitleGenerator.fallbackTitle(
                for: text,
                hasImages: !images.isEmpty
            )
            conversation.title = provisional
            if !text.isEmpty {
                requestTitleGeneration(from: text, provisionalTitle: provisional)
            }
        }
        conversation.updatedAt = .now

        requestAssistantReply()
    }
```

- [ ] **Step 6: Update `saveEdit(_:newText:)` guard**

In `saveEdit(_:newText:)` (line 463), replace:

```swift
        guard !trimmed.isEmpty || !message.imageAttachments.isEmpty else { return }
```

with:

```swift
        guard !trimmed.isEmpty || !message.imageAttachments.isEmpty || !message.documentAttachments.isEmpty else { return }
```

- [ ] **Step 7: Update `requestAssistantReply()` to pass `includeDocuments`**

In `requestAssistantReply()`, add `let supportsFiles = model.supportsFiles` after line 514 (`let supportsVision = model.supportsVision`):

```swift
        let supportsTools = model.supportsTools
        let supportsVision = model.supportsVision
        let supportsFiles = model.supportsFiles
        let supportsImageGen = model.supportsImageGen
```

And update the `apiHistoryTurns` call (lines 520-526):

```swift
        let historyTurns = ConversationCompactionService.apiHistoryTurns(
            sortedMessages: conversation.sortedMessages,
            compactedSummary: conversation.compactedSummary.isEmpty ? nil : conversation.compactedSummary,
            compactedThroughMessageID: conversation.compactedThroughMessageID,
            includeImages: supportsVision,
            includeDocuments: supportsFiles,
            excludingMessageID: assistantMessage.id
        )
```

- [ ] **Step 8: Build to verify no compile errors**

Run: `xcodebuild build -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```bash
git add OpenChat/Features/Chat/ChatViewModel.swift
git commit -m "feat: wire document attachments through ChatViewModel"
```

---

### Task 9: `ComposerTextView` paste-document hook

**Files:**
- Modify: `OpenChat/Features/Chat/ComposerTextView.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `PasteInterceptingTextView.onPasteDocument: ((Data, String?) -> Void)?`, `ComposerTextView.onPasteDocument: ((Data, String?) -> Void)?` (wired through `updateUIView`). Data is raw pasted bytes; filename is `nil` when the pasteboard has no filename hint (Task 11 applies the `"Document.pdf"` fallback).

- [ ] **Step 1: Add the property and paste interception**

Replace `PasteInterceptingTextView` (lines 10-25):

```swift
private final class PasteInterceptingTextView: UITextView {
    /// Called when the pasteboard contains one or more images.
    var onPasteImages: (([UIImage]) -> Void)?
    /// Called when the pasteboard contains a PDF document. Second argument is the
    /// pasteboard-provided filename hint, if any.
    var onPasteDocument: ((Data, String?) -> Void)?

    override func paste(_ sender: Any?) {
        if let images = UIPasteboard.general.images, !images.isEmpty, let onPasteImages {
            onPasteImages(images)
            return
        }

        if let onPasteDocument,
           let data = UIPasteboard.general.data(forPasteboardType: UTType.pdf.identifier) {
            let filename = UIPasteboard.general.itemProviders.first?.suggestedName
            onPasteDocument(data, filename)
            return
        }

        super.paste(sender)
    }
}
```

Add `import UniformTypeIdentifiers` after `import UIKit` (line 3):

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
```

- [ ] **Step 2: Add the `ComposerTextView` property and wire it**

Add a property after `onPasteImages` (line 38):

```swift
    var onPasteImages: (([UIImage]) -> Void)?
    /// Called when the user pastes a PDF into the composer.
    var onPasteDocument: ((Data, String?) -> Void)?
```

Update `updateUIView` (lines 81-83):

```swift
        if let pasteView = textView as? PasteInterceptingTextView {
            pasteView.onPasteImages = onPasteImages
            pasteView.onPasteDocument = onPasteDocument
        }
```

- [ ] **Step 3: Build to verify no compile errors**

Run: `xcodebuild build -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add OpenChat/Features/Chat/ComposerTextView.swift
git commit -m "feat: intercept PDF paste in ComposerTextView"
```

---

### Task 10: `DocumentPreviewView` (QuickLook)

**Files:**
- Create: `OpenChat/Features/Chat/DocumentPreviewView.swift`

**Interfaces:**
- Consumes: `ChatDocumentAttachment` (Task 1).
- Produces: `struct DocumentPreviewView: View` with `init(attachment: ChatDocumentAttachment)`, presentable via `.sheet(item:)`/`.fullScreenCover(item:)`.

- [ ] **Step 1: Write the implementation**

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
import QuickLook

struct DocumentPreviewView: View {
    let attachment: ChatDocumentAttachment
    @Environment(\.dismiss) private var dismiss
    @State private var previewURL: URL?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let previewURL {
                QuickLookPreview(url: previewURL).ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.28))
                    .padding(16)
            }
            .accessibilityLabel("Close preview")
        }
        .statusBarHidden(true)
        .task {
            previewURL = Self.writeTempFile(for: attachment)
        }
        .onDisappear {
            if let previewURL {
                try? FileManager.default.removeItem(at: previewURL)
            }
        }
    }

    private static func writeTempFile(for attachment: ChatDocumentAttachment) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(attachment.filename)
            try attachment.data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif
```

- [ ] **Step 2: Build to verify no compile errors**

Run: `xcodebuild build -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add OpenChat/Features/Chat/DocumentPreviewView.swift
git commit -m "feat: add DocumentPreviewView using QuickLook"
```

---

### Task 11: `MessageComposerView` document attach/paste/drop UI

**Files:**
- Modify: `OpenChat/Features/Chat/MessageComposerView.swift`

**Interfaces:**
- Consumes: `ChatDocumentAttachment`/`DocumentAttachmentEncoder` (Task 1), `ComposerTextView.onPasteDocument` (Task 9), `DocumentPreviewView` (Task 10).
- Produces: `MessageComposerView.documentAttachments: Binding<[ChatDocumentAttachment]>`, `MessageComposerView.supportsFiles: Bool` — both new required init params consumed by Task 13's `ChatView` call site.

- [ ] **Step 1: Add new bindings/params and state**

Add `documentAttachments` binding after `attachments` (line 21), and `supportsFiles` after `supportsVision` (line 22):

```swift
    @Binding var attachments: [ChatImageAttachment]
    @Binding var documentAttachments: [ChatDocumentAttachment]
    let supportsVision: Bool
    let supportsFiles: Bool
```

Add `showingFilesAlert` and `showingInvalidDocumentAlert` state after `showingVisionAlert` (line 48), and `previewDocument` after `previewAttachment` (line 54-55):

```swift
    @State private var showingVisionAlert = false
    @State private var showingFilesAlert = false
    @State private var showingInvalidDocumentAlert = false
```

```swift
    #if canImport(UIKit)
    @State private var previewAttachment: ChatImageAttachment?
    @State private var previewDocument: ChatDocumentAttachment?
    #endif
```

- [ ] **Step 2: Extend `canSend`**

Replace `canSend` (lines 58-60):

```swift
    private var canSend: Bool {
        !attachments.isEmpty || !documentAttachments.isEmpty || text.contains { !$0.isWhitespace }
    }
```

- [ ] **Step 3: Wire `.fileImporter`, extend `.onDrop`, add the alert and preview presentation**

Replace the `body` (lines 69-118):

```swift
    var body: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty || !documentAttachments.isEmpty {
                attachmentStrip
            }

            composerField
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(.bar)
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoPickerItems, maxSelectionCount: 4, matching: .images)
        .onChange(of: photoPickerItems) { _, items in
            Task { await loadPickerItems(items) }
        }
        .onDrop(of: [UTType.image, UTType.pdf], isTargeted: nil) { providers in
            handleDropProviders(providers)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            #if canImport(UIKit)
            CameraPicker(isPresented: $showingCamera) { image in
                appendImage(image)
            }
            .ignoresSafeArea()
            #else
            Color.clear.onAppear { showingCamera = false }
            #endif
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf]) { result in
            handleFileImporterResult(result)
        }
        .alert("Images not supported", isPresented: $showingVisionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let modelDisplayName {
                Text("\(modelDisplayName) can’t process images. Choose a model marked with an eye to attach or paste photos.")
            } else {
                Text("This model can’t process images. Choose a model marked with an eye to attach or paste photos.")
            }
        }
        .alert("Documents not supported", isPresented: $showingFilesAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let modelDisplayName {
                Text("\(modelDisplayName) can't process documents. Choose a model marked with a doc icon to attach or paste PDFs.")
            } else {
                Text("This model can't process documents. Choose a model marked with a doc icon to attach or paste PDFs.")
            }
        }
        .alert("Web search unavailable", isPresented: $showingWebSearchDisabledAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add a search API key in Settings → Web Search, then pick a provider from the web search button.")
        }
        .alert("Couldn't attach file", isPresented: $showingInvalidDocumentAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Couldn't attach that file — PDFs only, up to 32MB.")
        }
        #if canImport(UIKit)
        .fullScreenCover(item: $previewAttachment) { attachment in
            if let uiImage = UIImage(data: attachment.data) {
                ImagePreviewView(image: uiImage)
            }
        }
        .fullScreenCover(item: $previewDocument) { attachment in
            DocumentPreviewView(attachment: attachment)
        }
        #endif
    }
```

Add the `showingFileImporter` state alongside the others (line 51, after `showingCamera`):

```swift
    @State private var showingCamera = false
    @State private var showingFileImporter = false
```

- [ ] **Step 4: Update `ComposerTextView(...)` call**

Replace lines 131-137 in `composerField`:

```swift
            ComposerTextView(
                text: $text,
                placeholder: "Message",
                minHeight: 22,
                maxHeight: 120,
                onPasteImages: handlePastedImages,
                onPasteDocument: handlePastedDocument
            )
```

- [ ] **Step 5: Add menu items to `plusMenuButton`**

Replace `plusMenuButton` (lines 171-199):

```swift
    private var plusMenuButton: some View {
        Menu {
            if CameraCaptureAvailability.isAvailable {
                Button {
                    requestCamera()
                } label: {
                    Label("Camera", systemImage: "camera")
                }
            }

            Button {
                requestPhotoLibrary()
            } label: {
                Label("Photos", systemImage: "photo")
            }

            Button(action: pasteFromClipboard) {
                Label("Paste Image", systemImage: "doc.on.clipboard")
            }

            Button {
                requestFiles()
            } label: {
                Label("Browse Files", systemImage: "doc")
            }

            Button(action: pasteDocumentFromClipboard) {
                Label("Paste Document", systemImage: "doc.badge.clock")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Add")
        .accessibilityHint("Attach a photo, PDF, or paste content")
    }
```

- [ ] **Step 6: Extend `attachmentStrip` with PDF chips**

Replace `attachmentStrip` (lines 373-410):

```swift
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        #if canImport(UIKit)
                        if let uiImage = UIImage(data: attachment.data) {
                            Button {
                                Haptics.light()
                                previewAttachment = attachment
                            } label: {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Preview image")
                        }
                        #endif
                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .offset(x: 4, y: -4)
                        .accessibilityLabel("Remove image")
                    }
                }
                ForEach(documentAttachments) { document in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            Haptics.light()
                            previewDocument = document
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.accentColor)
                                Text(document.filename)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(Color.primary)
                                    .frame(maxWidth: 50)
                            }
                            .frame(width: 56, height: 56)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Preview document \(document.filename)")
                        Button {
                            documentAttachments.removeAll { $0.id == document.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .offset(x: 4, y: -4)
                        .accessibilityLabel("Remove document")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }
```

- [ ] **Step 7: Add file/paste/drop handlers**

Add after `requestCamera()` (lines 426-433):

```swift
    private func requestCamera() {
        guard supportsVision else {
            Haptics.warning()
            showingVisionAlert = true
            return
        }
        showingCamera = true
    }

    private func requestFiles() {
        guard supportsFiles else {
            Haptics.warning()
            showingFilesAlert = true
            return
        }
        showingFileImporter = true
    }
```

Add after `handlePastedImages(_:)` (lines 462-473):

```swift
    private func handlePastedImages(_ images: [UIImage]) {
        #if canImport(UIKit)
        guard supportsVision else {
            Haptics.warning()
            showingVisionAlert = true
            return
        }
        for image in images {
            appendImage(image)
        }
        #endif
    }

    private func handlePastedDocument(_ data: Data, filename: String?) {
        guard supportsFiles else {
            Haptics.warning()
            showingFilesAlert = true
            return
        }
        appendDocumentData(data, filename: filename ?? "Document.pdf")
    }
```

Replace `handleDropProviders(_:)` and `loadImages(from:)` (lines 475-494):

```swift
    private func handleDropProviders(_ providers: [NSItemProvider]) -> Bool {
        let hasImage = providers.contains { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        let hasPDF = providers.contains { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }

        if hasImage {
            guard supportsVision else {
                Haptics.warning()
                showingVisionAlert = true
                return false
            }
            loadImages(from: providers)
        }
        if hasPDF {
            guard supportsFiles else {
                Haptics.warning()
                showingFilesAlert = true
                return false
            }
            loadDocuments(from: providers)
        }
        return hasImage || hasPDF
    }

    private func loadImages(from providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    appendImageData(data)
                }
            }
        }
    }

    private func loadDocuments(from providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            let suggestedName = provider.suggestedName
            provider.loadDataRepresentation(forTypeIdentifier: UTType.pdf.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    appendDocumentData(data, filename: suggestedName ?? "Document.pdf")
                }
            }
        }
    }
```

Add `pasteDocumentFromClipboard()` after `pasteFromClipboard()` (lines 450-460):

```swift
    private func pasteFromClipboard() {
        #if canImport(UIKit)
        guard supportsVision else {
            Haptics.warning()
            showingVisionAlert = true
            return
        }
        guard let image = UIPasteboard.general.image else { return }
        appendImage(image)
        #endif
    }

    private func pasteDocumentFromClipboard() {
        guard supportsFiles else {
            Haptics.warning()
            showingFilesAlert = true
            return
        }
        guard let data = UIPasteboard.general.data(forPasteboardType: UTType.pdf.identifier) else { return }
        let filename = UIPasteboard.general.itemProviders.first?.suggestedName ?? "Document.pdf"
        appendDocumentData(data, filename: filename)
    }
```

Add `appendDocumentData(_:filename:)` after `appendImageData(_:)` (lines 513-519):

```swift
    @discardableResult
    private func appendImageData(_ data: Data) -> Bool {
        guard let attachment = ImageAttachmentEncoder.makeAttachment(from: data) else { return false }
        attachments.append(attachment)
        Haptics.light()
        return true
    }

    @discardableResult
    private func appendDocumentData(_ data: Data, filename: String) -> Bool {
        guard let attachment = DocumentAttachmentEncoder.makeAttachment(from: data, filename: filename) else {
            Haptics.warning()
            showingInvalidDocumentAlert = true
            return false
        }
        documentAttachments.append(attachment)
        Haptics.light()
        return true
    }
```

Add `handleFileImporterResult(_:)` after `appendImage(_:)` (before the closing brace, line 532):

```swift
    #if canImport(UIKit)
    private func appendImage(_ image: UIImage) {
        guard supportsVision else {
            Haptics.warning()
            showingVisionAlert = true
            return
        }
        guard let attachment = ImageAttachmentEncoder.makeAttachment(from: image) else { return }
        attachments.append(attachment)
        Haptics.light()
    }
    #endif

    private func handleFileImporterResult(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        appendDocumentData(data, filename: url.lastPathComponent)
    }
```

- [ ] **Step 8: Build to verify no compile errors**

Run: `xcodebuild build -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED (this task alone doesn't compile — `ChatView.swift`'s call site (Task 13) must also be updated since `MessageComposerView` now has two new required params. Build after Task 13 instead if doing Task 11 and 13 out of order; if executing in plan order, this build is expected to FAIL on `ChatView.swift`'s call site until Task 13 lands — note that and proceed.)

- [ ] **Step 9: Commit**

```bash
git add OpenChat/Features/Chat/MessageComposerView.swift
git commit -m "feat: add document attach/paste/drop UI to MessageComposerView"
```

---

### Task 12: `MessageBubbleView` document chip rendering + preview

**Files:**
- Modify: `OpenChat/Features/Chat/MessageBubbleView.swift`

**Interfaces:**
- Consumes: `ChatMessage.documentAttachments` (Task 2), `DocumentPreviewView` (Task 10).
- Produces: `MessageBubbleView.documentChipRow(_:alignment:)` (private), no new public interface — `message: ChatMessage` already carries `documentAttachments`.

- [ ] **Step 1: Add `previewDocument` state**

Replace lines 33-39:

```swift
    #if canImport(UIKit)
    @State private var previewAttachment: ChatImageAttachment?
    @State private var previewDocument: ChatDocumentAttachment?
    @State private var showingTextSelection = false
    @State private var shareAttachment: ChatImageAttachment?
    #endif
    @State private var draftText: String = ""
    @State private var reviewingSkillProposal: SkillProposal?
```

- [ ] **Step 2: Add preview presentation modifier**

Replace `body` (lines 41-67):

```swift
    var body: some View {
        Group {
            switch message.role {
            case .user:
                userBubble
            case .assistant:
                assistantContent
            case .system, .tool:
                EmptyView()
            }
        }
        #if canImport(UIKit)
        .fullScreenCover(item: $previewAttachment) { attachment in
            if let uiImage = UIImage(data: attachment.data) {
                ImagePreviewView(image: uiImage)
            }
        }
        .fullScreenCover(item: $previewDocument) { attachment in
            DocumentPreviewView(attachment: attachment)
        }
        .sheet(isPresented: $showingTextSelection) {
            TextSelectionSheet(text: displayContent)
        }
        .sheet(item: $shareAttachment) { attachment in
            if let uiImage = UIImage(data: attachment.data) {
                ActivityShareSheet(activityItems: [uiImage])
            }
        }
        #endif
    }
```

- [ ] **Step 3: Render document chips in `userBubble`**

Replace `userBubble` (lines 69-96):

```swift
    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 8) {
                if !message.imageAttachments.isEmpty {
                    attachmentGallery(message.imageAttachments, alignment: .trailing)
                }
                if !message.documentAttachments.isEmpty {
                    documentChipRow(message.documentAttachments, alignment: .trailing)
                }
                if isEditing {
                    editingBubble
                } else {
                    if !message.content.isEmpty {
                        userBubbleText
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
```

- [ ] **Step 4: Extend `editingBubble` Save/Send disabled condition**

In `editingBubble`, replace the Save/Send button's `.disabled(...)` (line 152):

```swift
                Button("Save · Send") {
                    Haptics.light()
                    onSaveEdit?(draftText)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && message.imageAttachments.isEmpty
                        && message.documentAttachments.isEmpty
                )
```

- [ ] **Step 5: Render document chips in `assistantContent`**

In `assistantContent` (lines 157-229), add a document chip block parallel to the existing image gallery block (which sits right after `VStack(alignment: .leading, spacing: 8) {`):

```swift
                if !message.imageAttachments.isEmpty {
                    attachmentGallery(message.imageAttachments, alignment: .leading)
                }
                if !message.documentAttachments.isEmpty {
                    documentChipRow(message.documentAttachments, alignment: .leading)
                }
```

- [ ] **Step 6: Add the `documentChipRow(_:alignment:)` method**

Add this new private method after `attachmentGallery(_:alignment:)` (after line 370, before `saveToPhotos(_:)`):

```swift
    private func documentChipRow(_ attachments: [ChatDocumentAttachment], alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            ForEach(attachments) { attachment in
                Button {
                    Haptics.light()
                    #if canImport(UIKit)
                    previewDocument = attachment
                    #endif
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(attachment.filename)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(Color.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview document \(attachment.filename)")
                .accessibilityHint("Opens document preview")
            }
        }
    }
```

- [ ] **Step 7: Build to verify no compile errors**

Run: `xcodebuild build -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add OpenChat/Features/Chat/MessageBubbleView.swift
git commit -m "feat: render document attachments in MessageBubbleView"
```

---

### Task 13: `ChatView` — wire `MessageComposerView`'s new params

**Files:**
- Modify: `OpenChat/Features/Chat/ChatView.swift`

**Interfaces:**
- Consumes: `ChatViewModel.pendingDocumentAttachments`, `ChatViewModel.supportsFiles` (Task 8), `MessageComposerView.documentAttachments`/`supportsFiles` (Task 11).
- Produces: nothing new — this is the final wiring point; after this task the app builds end-to-end.

- [ ] **Step 1: Update the `MessageComposerView(...)` call in `ChatComposerHost`**

In `OpenChat/Features/Chat/ChatView.swift`, replace the `MessageComposerView(...)` call inside `ChatComposerHost.body` (lines 175-201):

```swift
            MessageComposerView(
                text: $viewModel.composerText,
                attachments: $viewModel.pendingAttachments,
                documentAttachments: $viewModel.pendingDocumentAttachments,
                supportsVision: viewModel.supportsVision,
                supportsFiles: viewModel.supportsFiles,
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
                skills: skills,
                onSend: onSend,
                onStop: viewModel.cancelStreaming
            )
            .disabled(viewModel.editingMessageID != nil)
```

- [ ] **Step 2: Build to verify the full app compiles**

Run: `xcodebuild build -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run the full test suite**

Run: `xcodebuild test -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: PASS — all existing tests plus every test added in Tasks 1-7.

- [ ] **Step 4: Commit**

```bash
git add OpenChat/Features/Chat/ChatView.swift
git commit -m "feat: wire document attachments into ChatView composer"
```

---

### Task 14: Manual verification

**Files:** none (verification only, no code changes).

**Interfaces:** none.

- [ ] **Step 1: Attach via Browse Files**

Open a chat with a file-capable model (a doc icon shown in the model picker). Tap `+` → Browse Files, pick a PDF. Confirm it appears as a chip in the composer's attachment strip with a truncated filename.

- [ ] **Step 2: Paste a PDF via the menu and via in-field ⌘V**

Copy a PDF to the system pasteboard (e.g. share sheet "Copy" on a Files app PDF). In the composer, tap `+` → Paste Document, confirm it attaches. Separately, focus the text field and press ⌘V (external keyboard) or long-press → Paste; confirm the PDF attaches instead of pasting as text.

- [ ] **Step 3: Drag & drop a PDF**

From Files app in split view (iPad) or Files picker drag session, drag a PDF onto the composer. Confirm it attaches.

- [ ] **Step 4: Attempt each method on a non-file-capable model**

Switch to a model without the doc capability badge. Attempt Browse Files, Paste Document, and drag & drop. Confirm each shows the "Documents not supported" alert and nothing is attached.

- [ ] **Step 5: Switch models mid-thread with existing/pending documents**

With a thread containing a sent PDF (or a pending unsent PDF in the composer), switch to a model lacking file support. Confirm the "Switch model?" confirmation dialog appears, names the lost documents, and mentions unsent attachments being removed when applicable.

- [ ] **Step 6: Send to both provider formats**

Send a PDF with a question to an Anthropic model, confirm it answers about the PDF's content. Repeat with an OpenRouter (OpenAI-compatible) model. Confirm both work.

- [ ] **Step 7: Tap a document chip to preview**

In both the composer strip and a sent message bubble, tap a PDF chip/row. Confirm `DocumentPreviewView` opens via QuickLook, renders the PDF, and the close button dismisses it.

- [ ] **Step 8: Edit a user message containing only a document**

Send a message with a PDF and no text. Edit it (if editing is available for that message) and confirm the Save · Send button is enabled even with empty text, since the document attachment alone satisfies the guard.

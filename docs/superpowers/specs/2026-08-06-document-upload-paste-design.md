# PDF Document Upload / Paste — Design

## Summary

Add PDF attachments to the chat composer for models that can process
documents, mirroring the existing image-attachment feature end to end:
attach via a Files picker, paste from the clipboard (both the composer's
`+` menu and in-field ⌘V/long-press paste), or drag-and-drop; send as a
native `document`/`file` content part to providers that support it;
gate the affordances behind the model's capability so users on
non-file-capable models get the same "choose a different model" alert
pattern already used for vision.

Scope is intentionally **PDF only**. Both Anthropic's Messages API
(`document` content block, `media_type: application/pdf`) and the
OpenAI-compatible `file` content part (`file_data` as a
`data:application/pdf;base64,...` URI, used by OpenAI and proxied
as-is by OpenRouter) only accept PDF as a native document/file type.
Other formats (docx, csv, txt) aren't accepted as document blocks by
either wire format and would require a client-side text-extraction
pipeline — out of scope here.

## Background

OpenChat is a native Swift/SwiftUI iOS app with two provider wire
formats (`APIFormat.openAI`, `APIFormat.anthropic`) and one capability
badge system (`ModelCapability`) shown in the model picker. Critically,
`ModelCapability.files` **already exists** and is **already inferred
correctly** from provider catalogs — it's just unused for gating actual
requests:

- `ProviderModelsClient.decodeAnthropicModels` sets `.files` from
  Anthropic's `/models` response (`capabilities.pdf_input.supported`).
- `ModelCapability.inferred` sets `.files` from OpenRouter-style
  `architecture.input_modalities` containing `"file"`.

So no catalog/inference changes are needed — this feature is purely
about wiring the existing `.files` signal through the send path, and
building the attach/paste/drop UI that produces `ChatDocumentAttachment`
values, the same way `.vision` already gates `ChatImageAttachment`.

The image-attachment feature is the direct precedent for every part of
this design:

- **Model**: `ChatImageAttachment` (`Models/ChatImageAttachment.swift`)
  — `id`, `mimeType`, `data`, `dataURI`. Persisted on `ChatMessage` as
  JSON in `attachmentsData` → computed `imageAttachments`.
- **Turn**: `ChatTurn.images: [ChatImageAttachment]` /
  `hasImages`, built by `ChatRequestHistory.turns(from:includeImages:)`
  and `ConversationCompactionService.apiHistoryTurns(includeImages:)`.
- **Wire format**: `MultimodalRequestEncoder.openAIParts` /
  `.anthropicParts` build provider-specific content parts from
  `turn.images`.
- **Composer**: `MessageComposerView` — `+` menu (Camera / Photos /
  Paste Image), `.photosPicker`, `.onDrop(of: [.image])`, attachment
  strip with thumbnails + remove button, `showingVisionAlert` gating on
  `supportsVision`.
- **In-field paste**: `ComposerTextView.swift`'s
  `PasteInterceptingTextView.paste()` already intercepts image pastes
  via `onPasteImages`, and has a standing comment earmarking this exact
  extension:

  ```swift
  // Future document support: inspect UIPasteboard.general.itemProviders
  // for UTType.pdf / UTType.fileURL and emit `.document(Data)` here.
  ```

- **Bubble rendering**: `MessageBubbleView.attachmentGallery` renders
  `message.imageAttachments` for both sent and received turns, tappable
  into `ImagePreviewView`.
- **Model switching**: `ChatViewModel.selectModel` builds a
  `PendingModelSwitch` warning when switching away from vision loses
  thread images or clears unsent attachments (`omitsThreadImages`,
  `clearsPendingAttachments`).

Every piece below is a parallel structure to one of these, not a new
pattern.

## Data model & storage

### `ChatDocumentAttachment` (new — `Models/ChatDocumentAttachment.swift`)

```swift
struct ChatDocumentAttachment: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var filename: String
    var mimeType: String   // always "application/pdf"
    var data: Data

    var dataURI: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}
```

Same shape as `ChatImageAttachment` plus `filename` (needed for display
in the attachment chip/gallery and for the `file.filename` wire field;
images don't need this since they render as thumbnails).

### `DocumentAttachmentEncoder` (new, same file)

```swift
enum DocumentAttachmentEncoder {
    static let maxByteCount = 32 * 1024 * 1024 // 32MB — Anthropic & OpenAI PDF cap

    static func makeAttachment(from data: Data, filename: String) -> ChatDocumentAttachment? {
        guard data.count <= maxByteCount, data.starts(with: [0x25, 0x50, 0x44, 0x46]) else { return nil } // "%PDF"
        return ChatDocumentAttachment(filename: filename, mimeType: "application/pdf", data: data)
    }
}
```

Fails closed (returns `nil`) on oversized or non-PDF data, same as
`ImageAttachmentEncoder.makeAttachment` returning `nil` on undecodable
image data. The composer shows a one-line alert on `nil` ("Couldn't
attach that file — PDFs only, up to 32MB.").

### `ChatMessage`

Add, parallel to `attachmentsData`/`imageAttachments`:

```swift
var documentAttachmentsData: Data?

var documentAttachments: [ChatDocumentAttachment] {
    get { ... same JSON decode pattern ... }
    set { ... same JSON encode pattern ... }
}
```

Plus a `documentAttachments: [ChatDocumentAttachment] = []` init
parameter, same as `imageAttachments`.

### `ChatTurn`

Add `documents: [ChatDocumentAttachment] = []` and
`hasDocuments: Bool { !documents.isEmpty }`, parallel to `images`/
`hasImages`.

### `AIModel`

Add:

```swift
var supportsFiles: Bool { capabilities.contains(.files) }
```

Parallel to `supportsVision`/`supportsImageGen`. No decoding changes —
`.files` already round-trips through `capabilities`.

## Wire format

### `MultimodalRequestEncoder`

Generalize the Anthropic `ImageSource` struct (currently `type: "base64"`,
`mediaType`, `data`) since Anthropic's `document` source block is
byte-for-byte the same shape as its `image` source block — only the
outer `type` differs ("image" vs "document"). Rename to `Base64Source`
and reuse it for both parts.

Add a document/file variant to each part type:

```swift
struct OpenAIPart: Encodable, Equatable {
    var type: String
    var text: String?
    var imageURL: ImageURL?
    var file: FileData?          // new

    struct FileData: Encodable, Equatable {
        var filename: String
        var fileData: String     // "data:application/pdf;base64,..."
        enum CodingKeys: String, CodingKey { case filename, fileData = "file_data" }
    }
}

struct AnthropicPart: Encodable, Equatable {
    var type: String
    var text: String?
    var source: Base64Source?    // renamed from ImageSource, reused for both
}
```

`openAIParts(for:)` / `anthropicParts(for:)` gain a document branch
before the trailing text part, ordered `documents`, then `images`, then
`text` (order doesn't matter functionally to either provider; keeping
attachments before text matches the existing image convention and
Anthropic's documented recommendation to place document/image blocks
before the text that references them).

`hasImages` stays as its own guard; add a parallel `hasDocuments` guard
so a turn with only documents (no images) still produces parts.

### History / compaction

- `ChatRequestHistory`: add `includeDocuments: Bool` parameter to
  `turns(from:includeImages:excludingMessageID:)`, mirroring
  `includeImages`. When `false` and the message has documents, append
  `"[Document omitted — this model can't process documents]"` the same
  way the existing `omittedImagePlaceholder` works.
- `ConversationCompactionService.apiHistoryTurns`: add
  `includeDocuments: Bool = true`, threaded into
  `ChatRequestHistory.turns`. Eligibility filter
  (`!$0.content.isEmpty || !$0.imageAttachments.isEmpty`) also needs
  `|| !$0.documentAttachments.isEmpty` so document-only messages aren't
  dropped from the transcript.
- `ChatViewModel.requestAssistantReply()`: pass
  `includeDocuments: model.supportsFiles` alongside the existing
  `includeImages: supportsVision`.

## UI / UX & capability gating

### `ChatViewModel`

- New `var pendingDocumentAttachments: [ChatDocumentAttachment] = []`,
  parallel to `pendingAttachments`.
- New `var supportsFiles: Bool { currentModel?.supportsFiles ?? false }`.
- `send()`: guard `!documents.isEmpty && !supportsFiles` the same way
  it guards `!images.isEmpty && !supportsVision` today, setting
  `capabilityWarning` from a new `ChatServiceError.modelLacksFiles`
  case ("This model can't process documents. Choose a model marked
  with a doc icon."). Build the `ChatMessage` with
  `documentAttachments: documents` alongside `imageAttachments: images`.
- `selectModel()`: extend `PendingModelSwitch` with
  `omitsThreadDocuments: Bool` and fold pending-document clearing into
  `clearsPendingAttachments` (rename semantics stay the same — "unsent
  attachments" already reads generically). `PendingModelSwitch.message`
  gets a documents clause parallel to the images clause.
- `applyModelSelection`: clears `pendingDocumentAttachments` under the
  same condition as `pendingAttachments`.

### `MessageComposerView`

- New `@Binding var documentAttachments: [ChatDocumentAttachment]` and
  `let supportsFiles: Bool`, wired from `ChatView` to
  `viewModel.pendingDocumentAttachments` / `viewModel.supportsFiles`.
- **`+` menu**: two new items below "Paste Image":
  - **"Browse Files"** — `.fileImporter(isPresented:allowedContentTypes: [.pdf])`,
    gated on `supportsFiles` exactly like "Photos"/"Camera" gate on
    `supportsVision` (shows `showingFilesAlert` otherwise).
  - **"Paste Document"** — reads
    `UIPasteboard.general.data(forPasteboardType: UTType.pdf.identifier)`
    synchronously (same style as `pasteFromClipboard()`'s
    `UIPasteboard.general.image` read), feeds through
    `DocumentAttachmentEncoder`.
- **In-field paste**: `ComposerTextView`'s `onPasteDocument:
  ((Data, String?) -> Void)?` closure, checked in
  `PasteInterceptingTextView.paste()` right after the existing image
  check, before falling through to `super.paste()` — this is the exact
  spot flagged by the standing TODO comment. Filename is best-effort
  (pasteboard doesn't reliably provide one for raw PDF data); falls
  back to `"Document.pdf"`.
- **Drag & drop**: `.onDrop(of: [UTType.image, UTType.pdf], ...)`,
  branching per-`NSItemProvider` on which type identifier it conforms
  to.
- **Attachment strip**: PDF entries render as a distinct chip (doc
  icon + truncated filename, not a thumbnail) in the same horizontal
  strip as image thumbnails, with the same top-trailing remove (×)
  button. Tapping opens a new `DocumentPreviewView` (thin
  `QLPreviewController` `UIViewControllerRepresentable`, same role as
  `ImagePreviewView`).
- **Alert**: new `showingFilesAlert` state + message, parallel to
  `showingVisionAlert`.
- `canSend` already checks `!attachments.isEmpty || text.contains {...}`
  — extend to `!attachments.isEmpty || !documentAttachments.isEmpty || ...`.

### `MessageBubbleView`

- Render `message.documentAttachments` as a chip row using the same
  component the composer's attachment strip uses, placed alongside the
  existing `attachmentGallery` call for both `.trailing` (user) and
  `.leading` (assistant, in case a provider ever echoes a file back —
  unlikely today but keeps the rendering path symmetric) alignments.
  Tap opens `DocumentPreviewView`.

## Error handling

- Invalid/oversized PDF on attach → `DocumentAttachmentEncoder` returns
  `nil`, composer shows a lightweight one-shot alert, nothing is added
  to `pendingDocumentAttachments`.
- Attach/paste attempted on a non-file-capable model →
  `showingFilesAlert`, exactly like the vision alert; nothing added.
- Switching to a non-file-capable model mid-thread → `PendingModelSwitch`
  confirmation naming both lost thread documents and cleared pending
  attachments, same UX as the existing vision case.
- Sending to a model that stopped supporting files between compose and
  send (edge case, e.g. a stale picker state) → same guard as `send()`'s
  existing vision check, surfaced via `capabilityWarning`.

## Testing

Unit tests (Swift Testing, following `OpenChatTests`' existing patterns
for the image equivalents):

- `DocumentAttachmentEncoder`: valid PDF header accepted; non-PDF data
  rejected; oversized (>32MB) rejected.
- `MultimodalRequestEncoder`: OpenAI `file` part shape (`file_data` URI,
  filename) and Anthropic `document` part shape (`base64` source,
  `application/pdf` media type) for turns with documents only, images
  only, and both.
- `ChatMessage.documentAttachments`: JSON round-trip, empty → nil data.
- `ChatRequestHistory` / `ConversationCompactionService`: document
  omission placeholder when `includeDocuments: false`; document-only
  messages remain eligible for compaction transcripts.
- `PendingModelSwitch` construction in `ChatViewModel`-level tests (if
  such tests exist for the vision case) extended for the documents case.

Manual verification in the simulator (noted here since this isn't
scriptable in a unit test):

- Attach via "Browse Files", paste a copied PDF (menu button and
  in-field ⌘V), drag-and-drop a PDF onto the composer.
- Attempt each of the above on a non-file-capable model → alert shown,
  nothing attached.
- Switch models mid-thread with thread/pending documents present →
  confirmation dialog, correct behavior on confirm/cancel.
- Send a PDF to an Anthropic model and to an OpenRouter model; confirm
  the model can answer questions about the document content.

# Image Output Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the regenerate chip appear under every assistant response regardless of content type (text, image, or mixed), and let users long-press any image in the chat to Copy, Share, or Save it to Photos.

**Architecture:** In `MessageBubbleView.swift`, decouple `RegenerateChip`'s visibility from the existing `!displayContent.isEmpty` text guard so it renders for the last, non-streaming assistant message no matter what content it holds — no changes to the regenerate mechanism itself (`ChatViewModel.regenerateLastReply()` already handles images). Add a `.contextMenu` to each image rendered by `attachmentGallery(_:alignment:)` (shared by both user and assistant bubbles) with three actions: Copy (`UIPasteboard.general.image`), Share (a new `ActivityShareSheet` wrapping `UIActivityViewController`, presented via a new `shareAttachment` state + `.sheet(item:)`), and Save to Photos (`PHPhotoLibrary`, gated by a new `NSPhotoLibraryAddUsageDescription` Info.plist entry).

**Tech Stack:** Swift, SwiftUI, UIKit (`UIPasteboard`, `UIActivityViewController`), Photos framework (`PHPhotoLibrary`).

## Global Constraints

- iOS 17.0 deployment target (from `project.yml`).
- `MessageBubbleView.swift` has no automated test coverage today and this codebase has no SwiftUI view-testing library (no ViewInspector/snapshot testing target found in `OpenChatTests`). Follow the established precedent (see `docs/superpowers/plans/2026-08-05-edit-previous-messages.md`, Tasks 3–4): verify these changes by building and manually testing in the simulator, not with new XCTest files.
- Build with: `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'` (swap the simulator name if `iPhone 16` isn't installed locally). Requires a full Xcode install, not just Command Line Tools.
- `NSPhotoLibraryAddUsageDescription` is the narrower "add-only" permission required by `PHPhotoLibrary.requestAuthorization(for: .addOnly)` — distinct from the app's existing `NSPhotoLibraryUsageDescription` (read access, used elsewhere for image selection). Both must remain in `Info.plist`.
- Do not add a new "copy image" or "share" chip to the action row under the message — Copy/Share/Save live only in each image's long-press context menu, per the approved design (`docs/superpowers/specs/2026-08-05-image-output-actions-design.md`).

---

## File Structure

- **Modify** `OpenChat/Features/Chat/MessageBubbleView.swift`:
  - Split the `RegenerateChip` visibility guard so it renders for text, image, or mixed assistant replies.
  - Add `import Photos` alongside the existing `import UIKit`.
  - Add `@State private var shareAttachment: ChatImageAttachment?` and a `.sheet(item: $shareAttachment)` modifier.
  - Add `.contextMenu { ... }` to each image in `attachmentGallery`, with Copy, Share, and Save to Photos actions.
  - Add a new private `saveToPhotos(_:)` method.
  - Add a new private `ActivityShareSheet: UIViewControllerRepresentable` struct.
- **Modify** `OpenChat/Resources/Info.plist` — add `NSPhotoLibraryAddUsageDescription`.

---

### Task 1: Regenerate chip for every response type

**Files:**
- Modify: `OpenChat/Features/Chat/MessageBubbleView.swift:137-147`

**Interfaces:**
- No new public interfaces. Reuses the existing `onRetry: () -> Void`, `isLastMessage: Bool`, `message.isStreaming: Bool` already on `MessageBubbleView`.

No automated test for this task (SwiftUI view layout, no testable logic — see Global Constraints). Verified by build + manual simulator check in Step 2.

- [ ] **Step 1: Split the regenerate guard from the text guard**

In `OpenChat/Features/Chat/MessageBubbleView.swift`, replace lines 137-147:

```swift
                #if canImport(UIKit)
                if !displayContent.isEmpty {
                    HStack(spacing: 4) {
                        CopyChip(content: message.content)
                        SelectChip(isPresented: $showingTextSelection)
                        if isLastMessage && !message.isStreaming {
                            RegenerateChip(action: onRetry)
                        }
                    }
                }
                #endif
```

with:

```swift
                #if canImport(UIKit)
                if !displayContent.isEmpty {
                    HStack(spacing: 4) {
                        CopyChip(content: message.content)
                        SelectChip(isPresented: $showingTextSelection)
                        if isLastMessage && !message.isStreaming {
                            RegenerateChip(action: onRetry)
                        }
                    }
                } else if isLastMessage && !message.isStreaming {
                    RegenerateChip(action: onRetry)
                }
                #endif
```

- [ ] **Step 2: Build, then manually verify**

Run: `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

Then in the simulator:
- Generate an assistant reply that is image-only (no text) → confirm the regenerate chip (circular arrow icon) now appears under it, and tapping it regenerates the reply.
- Confirm a text-only reply and a mixed text+image reply still show the regenerate chip exactly as before (no regression, no duplicate chip).
- Confirm the chip is absent while the message is still streaming, and absent on any assistant message that isn't the last one.

- [ ] **Step 3: Commit**

```bash
git add OpenChat/Features/Chat/MessageBubbleView.swift
git commit -m "fix: show regenerate chip for image-only and mixed assistant replies"
```

---

### Task 2: Long-press Copy and Share on images

**Files:**
- Modify: `OpenChat/Features/Chat/MessageBubbleView.swift:6-31` (state), `:45-54` (body modifiers), `:238-260` (`attachmentGallery`), end of file (new `ActivityShareSheet`)

**Interfaces:**
- Consumes: existing `Haptics.light()`, `ChatImageAttachment` (`Identifiable`, has `.data: Data`).
- Produces: `@State private var shareAttachment: ChatImageAttachment?` and `private struct ActivityShareSheet: UIViewControllerRepresentable` — both consumed by Task 3 (Save to Photos is added to the same context menu).

No automated test for this task (see Global Constraints). Verified by build + manual simulator check in Step 4.

- [ ] **Step 1: Add `shareAttachment` state**

In `OpenChat/Features/Chat/MessageBubbleView.swift`, replace lines 28-31:

```swift
    #if canImport(UIKit)
    @State private var previewAttachment: ChatImageAttachment?
    @State private var showingTextSelection = false
    #endif
```

with:

```swift
    #if canImport(UIKit)
    @State private var previewAttachment: ChatImageAttachment?
    @State private var showingTextSelection = false
    @State private var shareAttachment: ChatImageAttachment?
    #endif
```

- [ ] **Step 2: Present the share sheet**

In `OpenChat/Features/Chat/MessageBubbleView.swift`, replace lines 45-54:

```swift
        #if canImport(UIKit)
        .fullScreenCover(item: $previewAttachment) { attachment in
            if let uiImage = UIImage(data: attachment.data) {
                ImagePreviewView(image: uiImage)
            }
        }
        .sheet(isPresented: $showingTextSelection) {
            TextSelectionSheet(text: displayContent)
        }
        #endif
```

with:

```swift
        #if canImport(UIKit)
        .fullScreenCover(item: $previewAttachment) { attachment in
            if let uiImage = UIImage(data: attachment.data) {
                ImagePreviewView(image: uiImage)
            }
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
```

- [ ] **Step 3: Add the context menu with Copy and Share**

In `OpenChat/Features/Chat/MessageBubbleView.swift`, replace the `attachmentGallery` method (lines 238-260):

```swift
    private func attachmentGallery(_ attachments: [ChatImageAttachment], alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            ForEach(attachments) { attachment in
                #if canImport(UIKit)
                if let uiImage = UIImage(data: attachment.data) {
                    Button {
                        Haptics.light()
                        previewAttachment = attachment
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260, maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview image")
                    .accessibilityHint("Opens full screen preview with zoom")
                }
                #endif
            }
        }
    }
```

with:

```swift
    private func attachmentGallery(_ attachments: [ChatImageAttachment], alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            ForEach(attachments) { attachment in
                #if canImport(UIKit)
                if let uiImage = UIImage(data: attachment.data) {
                    Button {
                        Haptics.light()
                        previewAttachment = attachment
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260, maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview image")
                    .accessibilityHint("Opens full screen preview with zoom")
                    .contextMenu {
                        Button {
                            UIPasteboard.general.image = uiImage
                            Haptics.light()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        Button {
                            shareAttachment = attachment
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                #endif
            }
        }
    }
```

- [ ] **Step 4: Add `ActivityShareSheet` and build**

In `OpenChat/Features/Chat/MessageBubbleView.swift`, add after the `PlainTextSelectionView` struct, still inside the trailing `#if canImport(UIKit)` block (i.e. immediately before the file's final `#endif`):

```swift
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

Run: `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

Then in the simulator:
- Long-press a user-sent image → confirm a context menu appears with "Copy" and "Share".
- Tap Copy, then paste into Notes (or another app) → confirm the image pastes.
- Tap Share → confirm the system share sheet opens with that image; dismiss it.
- Repeat for an assistant-generated image.
- In a multi-image assistant reply, long-press each image individually → confirm each menu's Copy/Share acts only on that specific image (paste after long-pressing the second image should yield the second image, not the first).

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Features/Chat/MessageBubbleView.swift
git commit -m "feat: add long-press copy and share actions to chat images"
```

---

### Task 3: Long-press Save to Photos

**Files:**
- Modify: `OpenChat/Features/Chat/MessageBubbleView.swift:1-4` (imports), `:238-273` (context menu — line numbers shifted by Task 2's edits), end of file
- Modify: `OpenChat/Resources/Info.plist:42-43`

**Interfaces:**
- Consumes: `shareAttachment` state and `attachmentGallery`'s `.contextMenu` block from Task 2.
- Produces: `private func saveToPhotos(_ image: UIImage)` on `MessageBubbleView`.

No automated test for this task (see Global Constraints). Verified by build + manual simulator check in Step 4 — Save to Photos additionally requires a real permission prompt, which can't be scripted in CI for this app.

- [ ] **Step 1: Import Photos**

In `OpenChat/Features/Chat/MessageBubbleView.swift`, replace lines 1-4:

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
```

with:

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
import Photos
#endif
```

- [ ] **Step 2: Add the Save to Photos menu item and method**

In `OpenChat/Features/Chat/MessageBubbleView.swift`, in `attachmentGallery`'s `.contextMenu` block (added in Task 2), add a third button after the Share button:

```swift
                    .contextMenu {
                        Button {
                            UIPasteboard.general.image = uiImage
                            Haptics.light()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        Button {
                            shareAttachment = attachment
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            saveToPhotos(uiImage)
                        } label: {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }
                    }
```

Then add the `saveToPhotos` method immediately after the closing brace of `attachmentGallery`:

```swift
    #if canImport(UIKit)
    private func saveToPhotos(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in Haptics.error() }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                Task { @MainActor in
                    success ? Haptics.success() : Haptics.error()
                }
            }
        }
    }
    #endif
```

- [ ] **Step 3: Add the `NSPhotoLibraryAddUsageDescription` permission string**

In `OpenChat/Resources/Info.plist`, replace lines 42-43:

```xml
	<key>NSPhotoLibraryUsageDescription</key>
	<string>OpenChat accesses photos you select so agents can analyze images.</string>
```

with:

```xml
	<key>NSPhotoLibraryAddUsageDescription</key>
	<string>OpenChat saves images to your photo library when you choose Save to Photos.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>OpenChat accesses photos you select so agents can analyze images.</string>
```

- [ ] **Step 4: Build, then manually verify**

Run: `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

Then in the simulator:
- Long-press any image → confirm the context menu now shows three items: Copy, Share, Save to Photos.
- Tap Save to Photos → confirm the iOS permission prompt appears (first time only), grant it → confirm a success haptic fires and the image appears in the simulator's Photos app.
- Reset photo permissions for the app (Settings → OpenChat → Photos → set to Never) and tap Save to Photos again → confirm an error haptic fires and the app does not crash.

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Features/Chat/MessageBubbleView.swift OpenChat/Resources/Info.plist
git commit -m "feat: add long-press save-to-photos action for chat images"
```

---

## Self-Review

**Spec coverage:**
- Regenerate chip visible for last assistant message regardless of text/image/mixed content → Task 1. ✅
- Long-press context menu on every rendered image (both `userBubble` and `assistantContent`, since both call `attachmentGallery`) → Tasks 2-3 modify the single shared `attachmentGallery` method, so both paths get the menu automatically. ✅
- Three actions: Copy, Share, Save to Photos → Task 2 (Copy, Share), Task 3 (Save to Photos). ✅
- Each image in a multi-image gallery gets its own independent context menu → `.contextMenu` is attached per-`ForEach`-iteration on each `Button`, scoped to that iteration's `attachment`/`uiImage` — verified manually in Task 2 Step 4. ✅
- No new chip in the action row for image actions → confirmed no changes to the `CopyChip`/`SelectChip`/`RegenerateChip` `HStack` region beyond Task 1's visibility fix. ✅
- No changes to `regenerateLastReply()`/`requestAssistantReply()` internals → not touched by any task. ✅
- `NSPhotoLibraryAddUsageDescription` added distinct from existing `NSPhotoLibraryUsageDescription` → Task 3, Step 3. ✅
- Error handling: denied/restricted photo permission and save failure both fire `Haptics.error()`, no crash → Task 3, Step 2. ✅

**Placeholder scan:** No "TBD"/"TODO"/"similar to Task N" found; every step has complete, real code.

**Type consistency:** `shareAttachment: ChatImageAttachment?` (Task 2, Step 1) matches the `.sheet(item: $shareAttachment)` closure parameter `attachment: ChatImageAttachment` (Task 2, Step 2) and the assignment `shareAttachment = attachment` inside the `ForEach` closure (Task 2, Step 3), where `attachment: ChatImageAttachment` is the loop variable. `ActivityShareSheet(activityItems: [Any])` (Task 2, Step 4) is called with `[uiImage]` where `uiImage: UIImage` (Task 2, Step 2) — matches. `saveToPhotos(_ image: UIImage)` (Task 3, Step 2) is called with `uiImage: UIImage` from the same `ForEach` scope — matches.

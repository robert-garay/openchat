# Status Bar / Live Activity / Notification Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the SF-Symbol-based Live Activity (Dynamic Island + Lock Screen) with the OpenChat ensō-ring mark — rotating while generating, solid green when ready, no text in the compact/minimal pill — and restructure the completion push notification into a clean title/subtitle/body layout.

**Architecture:** One new shared template imageset (`OpenChatMark`) compiled into both the `OpenChat` and `OpenChatLiveActivity` targets. `Status` gets `tintColor`/`elapsed` computed properties instead of `iconName`; a new `LiveActivityMark` view renders the tinted, rotating image everywhere an icon is shown today. `ContentState.detail` is deleted — every view derives its own text from `status` directly. `NotificationService` splits its single title string into title/subtitle/body.

**Tech Stack:** Swift 6, SwiftUI, ActivityKit, WidgetKit, XcodeGen (`project.yml` → `xcodegen generate`).

## Global Constraints

- Swift version `6.0`, iOS deployment target `17.0` (per `AGENTS.md`).
- No new dependencies.
- Do not add emojis to source files.
- Run `xcodegen generate` after any `project.yml` change and commit the regenerated `.xcodeproj`.
- Add a `CHANGELOG.md` bullet under `[Unreleased]` → `Changed` for this user-facing change.
- No unit tests exist for views/widgets in this codebase (per existing `OpenChatTests` and the design spec's Testing section) — verification here is build success + manual device/simulator check, not new XCTest files.

---

### Task 1: Add the shared `OpenChatMark` template asset

**Files:**
- Create: `OpenChat/Resources/SharedAssets.xcassets/Contents.json`
- Create: `OpenChat/Resources/SharedAssets.xcassets/OpenChatMark.imageset/Contents.json`
- Create: `OpenChat/Resources/SharedAssets.xcassets/OpenChatMark.imageset/OpenChatMark.png` (copy of `OpenChatLogo.png`)
- Create: `OpenChat/Resources/SharedAssets.xcassets/OpenChatMark.imageset/OpenChatMark@2x.png` (copy of `OpenChatLogo@2x.png`)
- Create: `OpenChat/Resources/SharedAssets.xcassets/OpenChatMark.imageset/OpenChatMark@3x.png` (copy of `OpenChatLogo@3x.png`)
- Modify: `project.yml`

**Interfaces:**
- Produces: an asset named `"OpenChatMark"` loadable via `Image("OpenChatMark")` in both the `OpenChat` and `OpenChatLiveActivity` targets, template-rendering so `.foregroundStyle(_:)` tints it.

- [ ] **Step 1: Create the catalog root**

```bash
mkdir -p "OpenChat/Resources/SharedAssets.xcassets/OpenChatMark.imageset"
```

Write `OpenChat/Resources/SharedAssets.xcassets/Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 2: Copy the existing ensō-ring artwork into the new imageset**

```bash
cp "OpenChat/Resources/Assets.xcassets/OpenChatLogo.imageset/OpenChatLogo.png" \
   "OpenChat/Resources/SharedAssets.xcassets/OpenChatMark.imageset/OpenChatMark.png"
cp "OpenChat/Resources/Assets.xcassets/OpenChatLogo.imageset/OpenChatLogo@2x.png" \
   "OpenChat/Resources/SharedAssets.xcassets/OpenChatMark.imageset/OpenChatMark@2x.png"
cp "OpenChat/Resources/Assets.xcassets/OpenChatLogo.imageset/OpenChatLogo@3x.png" \
   "OpenChat/Resources/SharedAssets.xcassets/OpenChatMark.imageset/OpenChatMark@3x.png"
```

(Reusing the light-mode artwork only — no dark-mode variant, since every
consumer of this asset explicitly tints it via `.foregroundStyle`.)

- [ ] **Step 3: Write the imageset's `Contents.json` as a template image**

Write `OpenChat/Resources/SharedAssets.xcassets/OpenChatMark.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "OpenChatMark.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "OpenChatMark@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "OpenChatMark@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "template-rendering-intent" : "template"
  }
}
```

- [ ] **Step 4: Wire the new catalog into both targets in `project.yml`**

In the `OpenChat` target's `sources:` list, add the new path alongside the
existing `Resources` exclude entry:

```yaml
  OpenChat:
    type: application
    platform: iOS
    sources:
      - path: OpenChat
        excludes:
          - "Resources/Info.plist"
      - path: OpenChat/Resources/SharedAssets.xcassets
```

In the `OpenChatLiveActivity` target's `sources:` list:

```yaml
  OpenChatLiveActivity:
    type: app-extension
    platform: iOS
    sources:
      - path: OpenChatLiveActivityExtension
      - path: OpenChat/Services/OpenChatLiveActivityAttributes.swift
      - path: OpenChat/Resources/SharedAssets.xcassets
```

- [ ] **Step 5: Regenerate the Xcode project and verify it builds**

```bash
xcodegen generate
xcodebuild -project OpenChat.xcodeproj -scheme OpenChat -destination 'generic/platform=iOS Simulator' build
```

Expected: build succeeds (no source changes reference the new asset yet —
this just confirms the catalog compiles into both targets cleanly).

- [ ] **Step 6: Commit**

```bash
git add OpenChat/Resources/SharedAssets.xcassets project.yml OpenChat.xcodeproj
git commit -m "feat: add shared OpenChatMark template asset for Live Activity"
```

---

### Task 2: Replace `iconName`/`detail` with `tintColor`/`elapsed` on `Status`/`ContentState`

**Files:**
- Modify: `OpenChat/Services/OpenChatLiveActivityAttributes.swift`
- Modify: `OpenChat/Services/LiveActivityService.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `OpenChatLiveActivityAttributes.Status.tintColor -> Color`,
  `OpenChatLiveActivityAttributes.Status.elapsed -> TimeInterval` (0 for
  non-generating states), `OpenChatLiveActivityAttributes.ContentState(status:)`
  (no `detail` parameter — Task 3/4 consume these).

- [ ] **Step 1: Rewrite the attributes file**

Replace the full contents of `OpenChat/Services/OpenChatLiveActivityAttributes.swift`:

```swift
import Foundation
import SwiftUI
import ActivityKit

/// Shared data shape for the OpenChat Live Activity. This file is included in both
/// the main app target and the Live Activity extension target.
struct OpenChatLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: Status
    }

    enum Status: Codable, Hashable {
        case generating(elapsed: TimeInterval)
        case completed
        case failed
    }

    var conversationTitle: String
    var modelName: String
}

extension OpenChatLiveActivityAttributes.Status {
    var tintColor: Color {
        switch self {
        case .generating: .accentColor
        case .completed: .green
        case .failed: .red
        }
    }

    /// Only meaningful while `.generating`; other states report 0.
    var elapsed: TimeInterval {
        if case .generating(let elapsed) = self { elapsed }
        else { 0 }
    }

    var isGenerating: Bool {
        if case .generating = self { true } else { false }
    }
}
```

- [ ] **Step 2: Update `LiveActivityService` to stop building `detail` strings**

In `OpenChat/Services/LiveActivityService.swift`, replace the `start`
initial state, the `update` method body, and the `end` method body:

```swift
    @discardableResult
    func start(conversationTitle: String, modelName: String?) async -> String? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }

        let attributes = OpenChatLiveActivityAttributes(
            conversationTitle: conversationTitle,
            modelName: modelName ?? "Assistant"
        )
        let initialState = OpenChatLiveActivityAttributes.ContentState(
            status: .generating(elapsed: 0)
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil),
                pushType: nil
            )
            activityIDs.insert(activity.id)
            return activity.id
        } catch {
            return nil
        }
    }

    /// Updates the Live Activity with a new status. Safe to call with a nil ID.
    func update(activityID: String?, status: OpenChatLiveActivityAttributes.Status) async {
        guard let activityID, activityIDs.contains(activityID) else { return }
        guard let activity = Activity<OpenChatLiveActivityAttributes>.activities.first(where: { $0.id == activityID }) else {
            activityIDs.remove(activityID)
            return
        }

        let contentState = OpenChatLiveActivityAttributes.ContentState(status: status)
        await activity.update(ActivityContent(state: contentState, staleDate: nil))
    }

    /// Ends the Live Activity, showing the final state for a moment before dismissal.
    func end(activityID: String?, status: OpenChatLiveActivityAttributes.Status = .completed) async {
        guard let activityID, activityIDs.remove(activityID) != nil else { return }
        guard let activity = Activity<OpenChatLiveActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }

        let finalState = OpenChatLiveActivityAttributes.ContentState(status: status)
        await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .default)
    }
```

The rest of the file (the `actor LiveActivityService` declaration, `shared`,
`activityIDs` storage) is unchanged.

- [ ] **Step 3: Build to confirm no other file references the removed members yet**

```bash
xcodebuild -project OpenChat.xcodeproj -scheme OpenChat -destination 'generic/platform=iOS Simulator' build
```

Expected: FAILS — `OpenChatLiveActivity.swift` and
`OpenChatLiveActivityViews.swift` still reference `iconName` and
`context.state.detail`. This confirms the old call sites exist; Tasks 3–4
fix them.

- [ ] **Step 4: Commit**

```bash
git add OpenChat/Services/OpenChatLiveActivityAttributes.swift OpenChat/Services/LiveActivityService.swift
git commit -m "refactor: replace Live Activity iconName/detail with tintColor/elapsed"
```

---

### Task 3: Add `LiveActivityMark` and redesign the compact/minimal Dynamic Island

**Files:**
- Modify: `OpenChatLiveActivityExtension/OpenChatLiveActivity.swift`

**Interfaces:**
- Consumes: `OpenChatLiveActivityAttributes.Status.tintColor`, `.elapsed`
  (Task 2); asset `"OpenChatMark"` (Task 1).
- Produces: `struct LiveActivityMark: View` with `init(status:)`, consumed
  by Task 4's expanded/Lock Screen views.

- [ ] **Step 1: Replace the file contents**

```swift
import WidgetKit
import SwiftUI

@main
struct OpenChatLiveActivity: WidgetBundle {
    var body: some Widget {
        OpenChatLiveActivityWidget()
    }
}

/// The OpenChat ensō-ring mark, tinted per Live Activity status and
/// rotating continuously while a response is generating. Used in every
/// Dynamic Island presentation and the Lock Screen banner so the brand mark
/// stays the single consistent visual across all of them.
struct LiveActivityMark: View {
    let status: OpenChatLiveActivityAttributes.Status

    var body: some View {
        Image("OpenChatMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(status.tintColor)
            .rotationEffect(.degrees(status.elapsed * Self.degreesPerSecond))
            .animation(.linear(duration: 1), value: status.elapsed)
    }

    /// One full rotation every 2 seconds, stepped by the ~1s Live Activity
    /// update cadence from `BackgroundGenerationService.notifyProgress`.
    private static let degreesPerSecond: Double = 180
}

struct OpenChatLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OpenChatLiveActivityAttributes.self) { context in
            OpenChatLiveActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    OpenChatLiveActivityExpandedLeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    OpenChatLiveActivityExpandedTrailing(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    OpenChatLiveActivityExpandedCenter(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    OpenChatLiveActivityExpandedBottom(context: context)
                }
            } compactLeading: {
                LiveActivityMark(status: context.state.status)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                LiveActivityMark(status: context.state.status)
                    .frame(width: 18, height: 18)
            }
        }
    }
}
```

- [ ] **Step 2: Build (still expected to fail on the other view file)**

```bash
xcodebuild -project OpenChat.xcodeproj -scheme OpenChat -destination 'generic/platform=iOS Simulator' build
```

Expected: FAILS only in `OpenChatLiveActivityViews.swift` (still references
`iconName`/`context.state.detail`). Confirms this file's changes are
correct in isolation.

- [ ] **Step 3: Commit**

```bash
git add OpenChatLiveActivityExtension/OpenChatLiveActivity.swift
git commit -m "feat: redesign compact/minimal Dynamic Island around the OpenChat mark"
```

---

### Task 4: Redesign the expanded Dynamic Island and Lock Screen views

**Files:**
- Modify: `OpenChatLiveActivityExtension/OpenChatLiveActivityViews.swift`

**Interfaces:**
- Consumes: `LiveActivityMark` (Task 3); `Status.tintColor`, `.elapsed`,
  `.isGenerating` (Task 2).

- [ ] **Step 1: Replace the file contents**

```swift
import WidgetKit
import SwiftUI

struct OpenChatLiveActivityLockScreenView: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            LiveActivityMark(status: context.state.status)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.conversationTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(context.attributes.modelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            LiveActivityStatusText(status: context.state.status)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct OpenChatLiveActivityExpandedLeading: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        LiveActivityMark(status: context.state.status)
            .frame(width: 28, height: 28)
    }
}

struct OpenChatLiveActivityExpandedTrailing: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        LiveActivityStatusText(status: context.state.status)
    }
}

struct OpenChatLiveActivityExpandedCenter: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        Text(context.attributes.conversationTitle)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
    }
}

struct OpenChatLiveActivityExpandedBottom: View {
    let context: ActivityViewContext<OpenChatLiveActivityAttributes>

    var body: some View {
        HStack {
            Text(context.attributes.modelName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

/// Live-ticking elapsed time while generating, or a static status word once
/// finished. Never shown in the compact/minimal Dynamic Island — those stay
/// icon-only.
struct LiveActivityStatusText: View {
    let status: OpenChatLiveActivityAttributes.Status

    var body: some View {
        if status.isGenerating {
            Text(timerInterval: (Date.now - status.elapsed)...(Date.now + 3600), countsDown: false)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else if case .failed = status {
            Text("Response failed")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Response ready")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: Regenerate the project (extension target file list unchanged, but confirm asset linkage) and build**

```bash
xcodebuild -project OpenChat.xcodeproj -scheme OpenChat -destination 'generic/platform=iOS Simulator' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OpenChatLiveActivityExtension/OpenChatLiveActivityViews.swift
git commit -m "feat: redesign expanded Dynamic Island and Lock Screen around the OpenChat mark"
```

---

### Task 5: Restructure the completion push notification

**Files:**
- Modify: `OpenChat/Services/NotificationService.swift:42-53`

**Interfaces:**
- Consumes: nothing new.
- Produces: no signature change to `scheduleResponseNotification` — same
  parameters, same call site in `BackgroundGenerationService`.

- [ ] **Step 1: Replace the content-building block**

In `OpenChat/Services/NotificationService.swift`, replace lines 42–53:

```swift
        let content = UNMutableNotificationContent()
        content.title = failed ? "OpenChat — Response failed" : "OpenChat — Response ready"
        let preview = messagePreview
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let trimmedPreview = preview.count > 120 ? String(preview.prefix(120)) + "…" : preview
        content.body = failed
            ? "Tap to view the details."
            : (trimmedPreview.isEmpty ? "Tap to read the response." : trimmedPreview)
        content.sound = failed ? nil : .default
        content.userInfo = ["conversationID": conversationID.uuidString]
        content.categoryIdentifier = "OPENCHAT_RESPONSE"
```

with:

```swift
        let content = UNMutableNotificationContent()
        content.title = "OpenChat"
        content.subtitle = failed ? "Couldn't finish" : "Response ready"
        let preview = messagePreview
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let trimmedPreview = preview.count > 120 ? String(preview.prefix(120)) + "…" : preview
        content.body = failed
            ? "Tap to see what happened."
            : (trimmedPreview.isEmpty ? "Tap to read the response." : trimmedPreview)
        content.sound = failed ? nil : .default
        content.userInfo = ["conversationID": conversationID.uuidString]
        content.categoryIdentifier = "OPENCHAT_RESPONSE"
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project OpenChat.xcodeproj -scheme OpenChat -destination 'generic/platform=iOS Simulator' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OpenChat/Services/NotificationService.swift
git commit -m "feat: restructure completion notification into title/subtitle/body"
```

---

### Task 6: Lint, changelog, final verification

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add the changelog entry**

Under `[Unreleased]` → `Changed` in `CHANGELOG.md`, add:

```markdown
- Redesigned the Live Activity (Dynamic Island + Lock Screen) and completion
  notification around the OpenChat mark: the compact/minimal Dynamic Island
  now shows only the rotating mark (no text), turning solid green when a
  response is ready; the notification splits into a clean title/subtitle/body
  layout.
```

- [ ] **Step 2: Run lint and tests**

```bash
./scripts/ci-lint.sh
./scripts/ci-test.sh
```

Expected: both pass. If `ci-lint.sh` flags anything in the touched files,
fix inline and re-run.

- [ ] **Step 3: Full build one more time**

```bash
xcodegen generate
xcodebuild -project OpenChat.xcodeproj -scheme OpenChat -destination 'generic/platform=iOS Simulator' build
```

Expected: BUILD SUCCEEDED, and `git status` shows no unexpected diff from
this regeneration (project.yml already matches what's committed).

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: note Live Activity and notification redesign in changelog"
```

---

## Manual Verification (post-implementation, not automated)

Live Activities do not render reliably in Simulator for the Dynamic Island
itself — verify on a physical Dynamic Island device where possible:

- Background the app and send a message: compact pill shows only the
  rotating accent-colored ring, no text.
- Response completes: ring stops rotating, turns solid green, no text, then
  the activity dismisses.
- Force a failure (e.g. airplane mode mid-generation): ring turns red,
  static.
- Long-press the compact pill mid-generation: expanded view shows the ring,
  conversation title, model name, and a live-ticking elapsed timer.
- Lock Screen during generation shows the same information in the banner
  layout.
- Notification banner on completion: title "OpenChat", subtitle "Response
  ready", body the response preview; tapping it opens the right
  conversation.
- Force a failure while backgrounded: subtitle "Couldn't finish", body "Tap
  to see what happened."
- Non-Dynamic-Island device: confirm the status-bar `minimal` presentation
  shows the same ring/tint behavior.

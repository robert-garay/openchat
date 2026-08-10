# Status Bar / Live Activity / Notification Redesign — Design

## Summary

Redesign the OpenChat Live Activity (Dynamic Island + Lock Screen) and the
local completion push notification around a single consistent brand mark —
the existing `OpenChatLogo` ensō ring — instead of per-state SF Symbols, and
strip text out of the always-visible Dynamic Island pill entirely. The ring
rotates while a response is generating and turns solid green, static, when
it's ready. The push notification is restructured into a clean three-tier
brand / status / content layout.

## Background

Today, `OpenChatLiveActivityAttributes.Status` maps each state to an SF
Symbol (`sparkles` / `checkmark.circle.fill` / `xmark.circle.fill`) and a
tint color. The Dynamic Island's `compactLeading` shows that symbol;
`compactTrailing` shows `Text(context.state.detail)` — a hand-written string
like "Generating response…" or "Still generating 2m…". The expanded Dynamic
Island regions and the Lock Screen view are plain default `HStack`/`VStack`
layouts using the same symbols. `NotificationService.scheduleResponseNotification`
sets `content.title` to `"OpenChat — Response ready"` / `"OpenChat — Response
failed"` and `content.body` to a truncated response preview, with no
subtitle used.

`OpenChatLogo` (`OpenChat/Resources/Assets.xcassets/OpenChatLogo.imageset`)
is a solid black ensō ring on a transparent background, marked
`template-rendering-intent: original` (does not tint as-is). It is currently
used only in `OpenChatLogoView` for the chat empty state and onboarding —
both full-color, non-template contexts that this change does not touch.

`BackgroundGenerationService.runStream` already calls `notifyProgress` at a
1-second cadence during streaming, which calls
`LiveActivityService.update(status: .generating(elapsed:))`. This existing
cadence is what drives the rotation.

App extensions have their own bundle and cannot read the host app's asset
catalog at runtime, so the Live Activity extension needs its own copy of the
mark asset.

## Scope

- Dynamic Island compact + minimal presentations: OpenChat ring only, no
  text, rotating while generating, solid green and static when ready, red
  and static on failure.
- Dynamic Island expanded presentation and the Lock Screen banner: same ring
  mark replaces the SF Symbols; typography and layout cleaned up; elapsed
  time during generation becomes a native live-ticking value instead of a
  hand-formatted string.
- Local push notification (`NotificationService.swift`): three-tier
  title/subtitle/body layout.

### Out of scope

- A Notification Content Extension (rich custom notification UI). The app
  icon shown in the standard notification banner is OS-controlled and
  already renders as the OpenChat icon; no code changes affect it.
- Changes to `OpenChatLogoView` or its two existing call sites (chat empty
  state, onboarding) — those stay full-color and unchanged.
- Notification grouping/threading (`threadIdentifier`) — not requested, not
  added.
- Any change to when Live Activities start/end or when notifications fire —
  purely a visual redesign of existing states.

## Architecture

1. Add a new template imageset, `OpenChatMark`, containing the same ensō
   ring artwork as `OpenChatLogo` but with `template-rendering-intent:
   template` (or rely on `.renderingMode(.template)` in code — see
   Components) so it can be tinted per state. Place it in a small shared
   assets catalog included in both the `OpenChat` and `OpenChatLiveActivity`
   target sources in `project.yml`, so the extension has its own compiled
   copy without bundling the full main-app asset catalog.
2. `OpenChatLiveActivityAttributes.Status` drops `iconName`; keeps a
   `tintColor` computed property (`.accentColor` / `.green` / `.red`).
3. The widget views (`OpenChatLiveActivityViews.swift`,
   `OpenChatLiveActivity.swift`) render `Image("OpenChatMark")` tinted per
   state, instead of `Image(systemName:)`.
4. Rotation angle is derived in the view from `context.state.status`'s
   `elapsed` (only present while `.generating`): `angle = elapsed *
   degreesPerSecond`, uncapped (keeps increasing, not modulo'd, so the
   `.animation(.linear(duration: 1), value: angle)` on the rotation
   modifier always interpolates forward into the next 1s update rather than
   snapping backward). Non-generating states pin the angle to its last
   value with no animation.
5. `NotificationService.scheduleResponseNotification` sets `title`,
   `subtitle`, and `body` as three distinct fields instead of folding status
   into `title`.

## Components

### `OpenChatMark.imageset` (new, shared)

New folder `OpenChat/Resources/SharedAssets.xcassets/OpenChatMark.imageset`
reusing the existing `OpenChatLogo` PNGs (1x/2x/3x, no dark-mode variant
needed since it's always explicitly tinted), with
`"template-rendering-intent" : "template"` in `Contents.json`.

`project.yml`: add `- path: OpenChat/Resources/SharedAssets.xcassets` to the
`sources:` list of both the `OpenChat` and `OpenChatLiveActivity` targets.
Run `xcodegen generate` after.

### `OpenChatLiveActivityAttributes.swift` (modified)

```swift
extension OpenChatLiveActivityAttributes.Status {
    var tintColor: Color {
        switch self {
        case .generating: .accentColor
        case .completed: .green
        case .failed: .red
        }
    }

    /// Only meaningful while `.generating`; other states ignore it.
    var elapsed: TimeInterval {
        if case .generating(let elapsed) = self { elapsed }
        else { 0 }
    }
}
```

`iconName` is removed — every state now renders the same `OpenChatMark`
image, differing only by tint (and rotation, for `.generating`).

### `OpenChatLiveActivity.swift` (modified)

`compactLeading` and `minimal` render a new shared subview,
`LiveActivityMark(status:)`, which applies the rotation + tint. `compactTrailing`
is removed (returns `EmptyView()` — Dynamic Island permits an empty trailing
slot).

```swift
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

    private static let degreesPerSecond: Double = 180
}
```

(180°/s → one full rotation every 2 seconds — a brisk but not frantic spin,
matched to the 1s update cadence so each step is a clean half-turn.)

### `OpenChatLiveActivityViews.swift` (modified)

- `OpenChatLiveActivityExpandedLeading` and `OpenChatLiveActivityLockScreenView`
  swap their `Image(systemName:)` for `LiveActivityMark(status: context.state.status)`,
  sized via `.frame(width:height:)` rather than `.font()` (image-based, not
  symbol-based).
- Elapsed time in the expanded/Lock Screen text: replace the hand-formatted
  `context.state.detail` string with a native live-ticking
  `Text(timerInterval:countsDown:)` while `.generating`, and a static
  "Response ready" / "Response failed" `Text` otherwise. The interval's
  start is derived in the view as `Date.now - status.elapsed` — no new field
  needed, since `Status.generating(elapsed:)` already carries everything
  required to reconstruct the start instant.
- Layout: mark leading, conversation title as primary text
  (`.font(.subheadline.weight(.semibold))`, `lineLimit(1)`), model name as
  `.caption`/`.secondary` beneath it — same information as today,
  restated with clearer hierarchy.

### `LiveActivityService.swift` (modified)

`ContentState.detail` is removed — the view now derives its own display
text from `status` alone (see above), so `update`/`end` no longer build a
`detail` string; they just construct `ContentState(status:)`. No other
signature changes; callers in `BackgroundGenerationService` are unaffected.

### `NotificationService.swift` (modified)

```swift
content.title = "OpenChat"
content.subtitle = failed ? "Couldn't finish" : "Response ready"
content.body = failed
    ? "Tap to see what happened."
    : (trimmedPreview.isEmpty ? "Tap to read the response." : trimmedPreview)
```

No change to scheduling, categories, or delegate handling.

## Error Handling

- **Live Activities disabled / unavailable:** unchanged — `LiveActivityService.start`
  already returns `nil` when `ActivityAuthorizationInfo().areActivitiesEnabled`
  is `false`, and every call site is already nil-safe.
- **Missing `OpenChatMark` asset at runtime:** `Image("OpenChatMark")` with a
  missing asset renders an empty view in SwiftUI rather than crashing;
  covered by manual verification (see Testing) rather than a runtime guard.
- **Rotation angle overflow:** `elapsed` is a `TimeInterval` (Double);
  `elapsed * 180` over a very long generation (hours) stays well within
  `Double` range and `.rotationEffect` normalizes angles internally, so no
  wraparound handling is needed.

## Testing

Views are not unit-tested in this codebase. `OpenChatLiveActivityAttributes.Status`
tint/elapsed computed properties are pure and small enough not to warrant
new unit tests beyond what already exists.

Manual simulator/device verification (Live Activities do not render in
Simulator reliably for Dynamic Island — verify on a physical Dynamic Island
device where possible, and Lock Screen presentation in Simulator otherwise):

- Start a generation with the app backgrounded on a Dynamic Island device:
  compact pill shows only the rotating accent-colored ring, no text.
- Response completes: ring stops rotating and turns solid green, still no
  text, then the activity dismisses per the existing `.default` dismissal
  policy.
- Force a failure (e.g. airplane mode mid-generation): ring turns red,
  static.
- Long-press the compact pill mid-generation: expanded view shows the ring,
  conversation title, model name, and a live-ticking elapsed timer.
- Lock Screen during generation shows the same information in the banner
  layout.
- Background the app during generation and let it complete: notification
  banner shows title "OpenChat", subtitle "Response ready", body the
  response preview; tapping it opens the right conversation (unchanged
  behavior).
- Force a failure while backgrounded: notification shows subtitle "Couldn't
  finish", body "Tap to see what happened."
- Non-Dynamic-Island device (or Simulator device without it): confirm the
  status-bar-icon presentation (`minimal`) also shows the same ring/tint
  behavior.

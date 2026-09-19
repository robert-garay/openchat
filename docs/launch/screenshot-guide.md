# App Store Screenshot Production Guide

## Required sizes (App Store Connect)

| Display | Size (pixels) | Device reference | Required? |
|---|---|---|---|
| 6.9" iPhone | 1320 × 2868 | iPhone 16 Pro Max | Yes (if available in ASC) |
| 6.7" iPhone | 1290 × 2796 | iPhone 15 Pro Max / 14 Pro Max | **Yes: primary** |
| 6.5" iPhone | 1284 × 2778 | iPhone 11 Pro Max / XS Max | Yes |
| 6.3" iPhone | 1206 × 2622 | iPhone 16 Pro | If targeting |
| 6.1" iPhone | 1179 × 2556 | iPhone 15 Pro / 14 Pro | If targeting |
| 5.5" iPhone | 1242 × 2208 | iPhone 8 Plus | Legacy; optional |
| 12.9" iPad Pro | 2048 × 2732 | iPad Pro 12.9" (portrait) | Yes if `TARGETED_DEVICE_FAMILY: 1,2` |
| 13" iPad Pro | 2064 × 2752 | iPad Pro 13" M4 | If available in ASC |

**Minimum for launch:** Capture on **6.7"** (1290 × 2796). ASC can scale for other iPhone sizes. Add iPad if shipping universal.

**Orientation:** Portrait only for iPhone screenshots.

## Dark vs light mode

| Shot | Recommended mode | Rationale |
|---|---|---|
| 1: Hero / welcome | Dark | Brand-forward; matches marketing landing page |
| 2: Active chat | Dark | Code blocks and Markdown look best on dark |
| 3: Model picker | Light | Provider logos and color tints pop on light |
| 4: Settings / BYOK | Light | Clean, trustworthy for "your keys" message |
| 5: Web search | Light | Settings UI clarity |
| 6: Rules or memory | Dark | Feature depth; matches chat aesthetic |
| 7: Skills (beta) | Dark | Composer slash menu visibility |
| 8: Background / Live Activity (optional) | Dark | Lock screen / Dynamic Island contrast |

Aim for **5–6 dark** and **2–3 light** for visual variety. Do not mix modes within a single screenshot.

## Shot-by-shot guide

### Shot 1: Hero

- **Screen:** Welcome / Connect a Provider (first launch or empty state)
- **Headline overlay:** "Every model. One app."
- **Subhead (optional):** "Your device. Your keys."
- **Sample prompt:** N/A (no chat visible)
- **Setup:** Fresh install or delete all providers. Dark mode.

### Shot 2: Active chat

- **Screen:** Chat view with streaming or completed assistant reply
- **Headline overlay:** "Native chat with Markdown & code"
- **Sample prompt (user message):** "Write a Swift function that debounces a search field using Combine."
- **Assistant reply:** Include a code block with syntax highlighting and a brief explanation. Use a real model response (not lorem ipsum).
- **Setup:** Dark mode. Hide any real API key balances. Use a generic model name like "GPT-4o" or "Claude Sonnet".

### Shot 3: Model picker

- **Screen:** Model selection sheet open, showing multiple providers
- **Headline overlay:** "Switch providers without switching apps"
- **Sample prompt:** N/A
- **Setup:** Connect 2–3 providers beforehand. Light mode. Ensure provider names are visible.

### Shot 4: Settings / Providers

- **Screen:** Settings → Providers list with 2–3 connected providers
- **Headline overlay:** "Your keys, your providers"
- **Subhead (optional):** "Bring your own key"
- **Setup:** Light mode. Blur or omit balance amounts if shown.

### Shot 5: Web search

- **Screen:** Settings → Tools → Web Search with one provider configured
- **Headline overlay:** "Optional web search, your keys"
- **Setup:** Light mode. Show provider name (e.g., Tavily) without exposing API key.

### Shot 6: Rules or memory

- **Screen:** Settings → Tools → Rules (global rules list) OR Memory settings
- **Headline overlay:** "Steer behavior with rules & memory"
- **Sample rule text:** "Always respond concisely. Prefer code examples in Swift."
- **Setup:** Dark mode. Use realistic but non-sensitive rule content.

### Shot 7: Skills (beta)

- **Screen:** Skills list + composer with "/" slash menu visible
- **Headline overlay:** "Reusable prompts with / commands"
- **Setup:** Create 2–3 sample skills (e.g., "Summarize", "Explain like I'm 5", "Review code"). Dark mode.

### Shot 8: Background generation (optional)

- **Screen:** Lock screen with Live Activity OR notification banner
- **Headline overlay:** "Replies finish in the background"
- **Setup:** Start a long generation, background the app. Capture Live Activity or notification. Dark mode.

## Pre-capture checklist

- [ ] Use iOS Simulator or physical device at exact resolution
- [ ] Set appearance mode per shot (see table above)
- [ ] Remove or blur any real API keys, balances, or personal data
- [ ] Use realistic but generic sample prompts (no client names, no secrets)
- [ ] Status bar: full signal, full battery, 9:41 AM (Apple convention)
- [ ] No notification badges unrelated to the demo
- [ ] Disable Voice Mode (hidden in 1.0 build)

## Recommended tools

| Tool | Use case | Export settings |
|---|---|---|
| **Xcode Simulator** | Raw screen captures at exact device resolution | File → Save Screen (⌘S) at 100% scale |
| **Screenshots.pro** | Add headline overlays and device frames | Export at native resolution; PNG; no compression |
| **Figma** | Custom frames, multi-size export | Export 1× at target pixel dimensions; PNG |
| **Previewed** | Quick device mockups with text overlays | Match ASC pixel dimensions; PNG |
| **Apple Frames (Figma community)** | Official-style device bezels | Export inner screen at exact ASC size |

**Workflow:** Capture raw screenshots in Simulator → add headline overlays in Screenshots.pro or Figma → export PNG at exact ASC dimensions (no JPEG).

## Overlay text guidelines

- Font: SF Pro Display (bold for headline, regular for subhead)
- Headline size: ~48–56 pt at 1290 px width
- Color: White text on dark screenshots; dark text (#1d1d1f) on light
- Position: Top third of screen, left-aligned with ~60 px margin
- Max 6–8 words per headline
- No emoji in overlay text

## Export and upload

1. Export each screenshot as PNG at exact pixel dimensions (no upscaling).
2. Upload to App Store Connect → App → [version] → Screenshots.
3. ASC accepts up to 10 screenshots per device size; use 6–8 for launch.
4. Order: Hero → Chat → Model picker → BYOK → Web search → Rules/Memory → Skills → Background (optional).

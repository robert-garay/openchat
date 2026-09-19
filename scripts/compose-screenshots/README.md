# Screenshot compositor (ChatGPT/Grok style)

Deterministic HTML/CSS compositor for App Store screenshots. Layers **real** simulator captures on **branded gradient backgrounds** with bold headline copy — no fake AI UI, no orbit-arc plate overlays.

## Layout

| Zone | Share of canvas | Content |
|---|---|---|
| Copy | Top ~33% | Centered headline + optional subhead |
| Device | Lower ~67% | Real capture in rounded phone frame (940 px wide) |
| Background | Full bleed | Dark violet gradient (`#6565E9` / `#7A7AFA`) or soft brand wash (light shots) |

Canvas: **1290 × 2796** (6.7" ASC primary). Brand tagline: *Every model. One app. Your device.*

## Prerequisites

| Requirement | Notes |
|---|---|
| **macOS** | Export script is Mac-only (`compose.sh`) |
| Raw captures | `shot-01.png` … `shot-07.png` in `screenshots/compose/raw/`, `screenshots/raw/`, or `screenshots/final/` |
| Headless browser | Google Chrome (preferred) or Playwright (`npx playwright install chromium`) |

Raw captures are produced on Mac with `./scripts/capture-screenshots.sh` (writes to `screenshots/raw/` by default). Copy or symlink into `screenshots/compose/raw/` if needed:

```bash
mkdir -p screenshots/compose/raw
cp screenshots/raw/shot-*.png screenshots/compose/raw/
```

Simulator captures are often **1320×2868** (iPhone 16 Pro Max). The compositor scales them inside the device frame at export width.

### Capture content requirements

| Shot | Raw screen | Capture notes |
|---|---|---|
| 01 | Welcome / Connect a Provider | Dark mode |
| 02 | Active chat + code | Dark mode; show **GPT-6 Astra** or **Claude Fable** in chat header |
| 03 | Model picker | Light mode; multiple providers visible |
| 04 | Settings → Providers | Light mode; **OpenRouter listed first**, then other providers |
| 05 | Web search settings | Light mode |
| 06 | Rules or memory | Dark mode |
| 07 | Skills + `/` menu | Dark mode |

## Usage

### Preview (any OS)

Open `scripts/compose-screenshots/index.html` in a browser. All seven shots stack vertically.

Single-shot export preview: append `?shot=01` (… `07`).

### Export (macOS only)

```bash
./scripts/compose-screenshots/compose.sh
```

Options:

```bash
./scripts/compose-screenshots/compose.sh --shot 03
./scripts/compose-screenshots/compose.sh --raw-dir screenshots/raw
OUT_DIR=/tmp/asc ./scripts/compose-screenshots/compose.sh
```

Output: `screenshots/final/chatgpt-style/shot-NN.png` (gitignored).

`--plate` is accepted as an alias for `--shot`.

## Shots

| Shot | Mode | Headline | Subhead |
|---|---|---|---|
| 01 | dark | Every model. One app. | Your device. Your keys. (+ brand tagline) |
| 02 | dark | Native chat with Markdown & code | — |
| 03 | light | Switch providers without switching apps | — |
| 04 | light | Your keys, your providers | Bring your own key |
| 05 | light | Optional web search, your keys | — |
| 06 | dark | Steer behavior with rules & memory | — |
| 07 | dark | Reusable prompts with / commands | — |

Copy matches `docs/launch/screenshot-guide.md`.

## Verification checklist

- [ ] All seven raw PNGs exist (compose/raw, raw, or final)
- [ ] `compose.sh` exits 0 on Mac
- [ ] Each output PNG is **1290×2796**
- [ ] Headlines match `screenshot-guide.md` verbatim
- [ ] Shot 02 header shows GPT-6 Astra or Claude Fable
- [ ] Shot 04 lists OpenRouter first
- [ ] No API keys, balances, or personal data visible in raw captures
- [ ] Upload order: 01 → 07 per ASC paste bundle

## Files

| File | Purpose |
|---|---|
| `index.html` | Seven `<section>` shots; `?shot=NN` for export |
| `compose.css` | Branded gradient + device frame geometry |
| `compose.sh` | Mac headless export to `screenshots/final/chatgpt-style/` |

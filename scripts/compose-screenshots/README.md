# Screenshot compositor

Deterministic HTML/CSS compositor for App Store screenshots. Layers **real** simulator captures and **real** OpenChat branding — no drawn UI chrome.

## Prerequisites

| Requirement | Notes |
|---|---|
| **macOS** | Export script is Mac-only (`compose.sh`) |
| Raw captures | `screenshots/compose/raw/shot-01.png` … `shot-07.png` |
| Brand assets | `website/assets/openchat-mark.png`, `openchat-logo-dark.png` (committed) |
| Headless browser | Google Chrome (preferred) or Playwright (`npx playwright install chromium`) |

Raw captures are produced on Mac with `./scripts/capture-screenshots.sh` (writes to `screenshots/raw/` by default). Copy or symlink into `screenshots/compose/raw/` before composing:

```bash
mkdir -p screenshots/compose/raw
cp screenshots/raw/shot-*.png screenshots/compose/raw/
```

Simulator captures are often **1320×2868** (iPhone 16 Pro Max). The compositor scales them into the **1290×2796** ASC 6.7" frame via `object-fit: cover`.

## Usage

### Preview (any OS)

Open `scripts/compose-screenshots/index.html` in a browser. All seven plates stack vertically.

Single-plate export preview: append `?plate=01` (… `07`) to hide other plates.

### Export (macOS only)

```bash
./scripts/compose-screenshots/compose.sh
```

Options:

```bash
./scripts/compose-screenshots/compose.sh --plate 03   # one plate
OUT_DIR=/tmp/asc ./scripts/compose-screenshots/compose.sh
```

Output: `screenshots/final/shot-NN.png` (gitignored).

## Plates

| Plate | Raw | Mode | Headline | Subhead | Mark |
|---|---|---|---|---|---|
| 01 | shot-01 | dark | Every model. One app. | Your device. Your keys. | 96×96 top-right (`openchat-mark.png`) |
| 02 | shot-02 | dark | Native chat with Markdown & code | — | — |
| 03 | shot-03 | light | Switch providers without switching apps | — | — |
| 04 | shot-04 | light | Your keys, your providers | Bring your own key | — |
| 05 | shot-05 | light | Optional web search, your keys | — | — |
| 06 | shot-06 | dark | Steer behavior with rules & memory | — | — |
| 07 | shot-07 | dark | Reusable prompts with / commands | — | — |

Copy matches `docs/launch/screenshot-guide.md` exactly.

## Geometry (1290×2796)

Derived from `screenshot-guide.md` overlay guidelines:

- Canvas: 1290 × 2796 px
- Headline: SF Pro Display bold, 52 px, left margin 60 px, top 132 px
- Subhead: SF Pro Display regular, 32 px, 16 px below headline
- Dark plates: white text + top gradient scrim
- Light plates: `#1d1d1f` text + light gradient scrim
- Plate 01 mark: 96 × 96 px, 60 px from top and right

## Verification checklist

- [ ] All seven raw PNGs exist under `screenshots/compose/raw/`
- [ ] `compose.sh` exits 0 on Mac
- [ ] Each `screenshots/final/shot-NN.png` is **1290×2796**
- [ ] Headlines match `screenshot-guide.md` verbatim
- [ ] Plate 01 shows `openchat-mark.png` at 96×96 top-right
- [ ] No API keys, balances, or personal data visible in raw captures
- [ ] Upload order: 01 → 07 per ASC paste bundle

## Files

| File | Purpose |
|---|---|
| `index.html` | Seven `<section>` plates; `?plate=NN` for export |
| `compose.css` | Fixed canvas + plate-specific layout |
| `compose.sh` | Mac headless export to `screenshots/final/` |

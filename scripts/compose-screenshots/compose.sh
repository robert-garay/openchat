#!/usr/bin/env bash
# Compose App Store screenshots from raw simulator captures + HTML/CSS overlays.
#
# macOS only — uses headless Chrome (preferred) or Playwright to export PNGs.
#
# Prerequisites:
#   - Raw captures in screenshots/compose/raw/shot-01.png … shot-07.png
#     (populate via capture-screenshots.sh on Mac, then copy or symlink)
#   - Google Chrome installed, OR: npx playwright + chromium
#
# Usage:
#   ./scripts/compose-screenshots/compose.sh
#   ./scripts/compose-screenshots/compose.sh --plate 03
#   OUT_DIR=screenshots/final ./scripts/compose-screenshots/compose.sh
#
# Output: screenshots/final/shot-NN.png at 1290×2796 (6.7" ASC primary size)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_DIR="$REPO_ROOT/scripts/compose-screenshots"
RAW_DIR="$REPO_ROOT/screenshots/compose/raw"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/screenshots/final}"
INDEX_HTML="$COMPOSE_DIR/index.html"
CANVAS_W=1290
CANVAS_H=2796

PLATES=(01 02 03 04 05 06 07)
SINGLE_PLATE=""

usage() {
  cat <<'EOF'
Usage: compose.sh [--plate NN]

Exports composed App Store screenshots (1290×2796 PNG) to screenshots/final/.

Requires macOS with Google Chrome or Playwright (npx playwright install chromium).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plate)
      SINGLE_PLATE="${2:?--plate requires a number, e.g. 03}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "compose.sh requires macOS (headless Chrome or Playwright)." >&2
  echo "Preview plates in a browser on any OS; export must run on Mac after raw captures exist." >&2
  exit 1
fi

if [[ -n "$SINGLE_PLATE" ]]; then
  PLATES=("$SINGLE_PLATE")
fi

missing=()
for plate in "${PLATES[@]}"; do
  raw="$RAW_DIR/shot-${plate}.png"
  if [[ ! -f "$raw" ]]; then
    missing+=("$raw")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Missing raw captures (populate screenshots/compose/raw/ first):" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

for asset in \
  "$REPO_ROOT/website/assets/openchat-mark.png" \
  "$REPO_ROOT/website/assets/openchat-logo-dark.png"
do
  [[ -f "$asset" ]] || { echo "Missing branding asset: $asset" >&2; exit 1; }
done

mkdir -p "$OUT_DIR"

find_chrome() {
  local candidates=(
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"
    "/Applications/Chromium.app/Contents/MacOS/Chromium"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

export_with_chrome() {
  local chrome="$1"
  local plate="$2"
  local outfile="$OUT_DIR/shot-${plate}.png"
  local url="file://${INDEX_HTML}?plate=${plate}"

  "$chrome" \
    --headless=new \
    --disable-gpu \
    --hide-scrollbars \
    --force-device-scale-factor=1 \
    --window-size="${CANVAS_W},${CANVAS_H}" \
    --screenshot="$outfile" \
    "$url" \
    >/dev/null 2>&1

  [[ -f "$outfile" ]] || return 1

  local dims
  dims=$(sips -g pixelWidth -g pixelHeight "$outfile" 2>/dev/null | awk '/pixel/{print $2}' | tr '\n' ' ')
  read -r w h <<<"$dims"
  if [[ "$w" != "$CANVAS_W" || "$h" != "$CANVAS_H" ]]; then
    echo "WARN: shot-${plate}.png is ${w}×${h}, expected ${CANVAS_W}×${CANVAS_H}" >&2
  fi
  echo "Exported: $outfile"
}

export_with_playwright() {
  local plate="$1"
  local outfile="$OUT_DIR/shot-${plate}.png"
  local url="file://${INDEX_HTML}?plate=${plate}"

  if ! command -v npx >/dev/null 2>&1; then
    return 1
  fi

  npx --yes playwright@1.49.1 screenshot \
    --browser=chromium \
    --viewport-size="${CANVAS_W},${CANVAS_H}" \
    --wait-for-timeout=500 \
    "$url" \
    "$outfile" \
    >/dev/null 2>&1

  [[ -f "$outfile" ]] || return 1
  echo "Exported (Playwright): $outfile"
}

CHROME=""
if CHROME=$(find_chrome); then
  echo "==> Using headless Chrome: $CHROME"
  for plate in "${PLATES[@]}"; do
    export_with_chrome "$CHROME" "$plate"
  done
  exit 0
fi

echo "==> Chrome not found; trying Playwright"
for plate in "${PLATES[@]}"; do
  export_with_playwright "$plate" || {
    echo "Export failed. Install Google Chrome or run: npx playwright install chromium" >&2
    exit 1
  }
done

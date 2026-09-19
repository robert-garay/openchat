#!/usr/bin/env bash
# Compose ChatGPT/Grok-style App Store screenshots from raw simulator captures.
#
# macOS only — uses headless Chrome (preferred) or Playwright to export PNGs.
#
# Prerequisites:
#   - Raw captures as shot-01.png … shot-07.png in one of:
#       screenshots/compose/raw/  (preferred)
#       screenshots/raw/
#       screenshots/final/         (fallback when reusing existing captures)
#   - Google Chrome installed, OR: npx playwright + chromium
#
# Usage:
#   ./scripts/compose-screenshots/compose.sh
#   ./scripts/compose-screenshots/compose.sh --shot 03
#   OUT_DIR=screenshots/final/chatgpt-style ./scripts/compose-screenshots/compose.sh
#
# Output: screenshots/final/chatgpt-style/shot-NN.png at 1290×2796 (6.7" ASC primary size)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_DIR="$REPO_ROOT/scripts/compose-screenshots"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/screenshots/final/chatgpt-style}"
INDEX_HTML="$COMPOSE_DIR/index.html"
CANVAS_W=1290
CANVAS_H=2796

SHOTS=(01 02 03 04 05 06 07)
SINGLE_SHOT=""
RAW_DIR=""

usage() {
  cat <<'EOF'
Usage: compose.sh [--shot NN] [--raw-dir PATH]

Exports ChatGPT/Grok-style App Store screenshots (1290×2796 PNG).

Raw captures: screenshots/compose/raw/, screenshots/raw/, or screenshots/final/.
Output default: screenshots/final/chatgpt-style/

Requires macOS with Google Chrome or Playwright (npx playwright install chromium).
EOF
}

resolve_raw_dir() {
  local candidate
  for candidate in \
    "$REPO_ROOT/screenshots/compose/raw" \
    "$REPO_ROOT/screenshots/raw" \
    "$REPO_ROOT/screenshots/final"
  do
    if [[ -f "$candidate/shot-01.png" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  echo "$REPO_ROOT/screenshots/compose/raw"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shot|--plate)
      SINGLE_SHOT="${2:?--shot requires a number, e.g. 03}"
      shift 2
      ;;
    --raw-dir)
      RAW_DIR="${2:?--raw-dir requires a path}"
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
  echo "Preview shots in a browser on any OS; export must run on Mac after raw captures exist." >&2
  exit 1
fi

if [[ -z "$RAW_DIR" ]]; then
  RAW_DIR="$(resolve_raw_dir)"
fi

if [[ -n "$SINGLE_SHOT" ]]; then
  SHOTS=("$SINGLE_SHOT")
fi

missing=()
for shot in "${SHOTS[@]}"; do
  raw="$RAW_DIR/shot-${shot}.png"
  if [[ ! -f "$raw" ]]; then
    missing+=("$raw")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Missing raw captures (checked screenshots/compose/raw/, screenshots/raw/, screenshots/final/):" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

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

build_url() {
  local shot="$1"
  local encoded_raw
  encoded_raw=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe="/"))' "$RAW_DIR")
  echo "file://${INDEX_HTML}?shot=${shot}&rawDir=${encoded_raw}"
}

export_with_chrome() {
  local chrome="$1"
  local shot="$2"
  local outfile="$OUT_DIR/shot-${shot}.png"
  local url
  url="$(build_url "$shot")"

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
    echo "WARN: shot-${shot}.png is ${w}×${h}, expected ${CANVAS_W}×${CANVAS_H}" >&2
  fi
  echo "Exported: $outfile"
}

export_with_playwright() {
  local shot="$1"
  local outfile="$OUT_DIR/shot-${shot}.png"
  local url
  url="$(build_url "$shot")"

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

echo "==> Raw captures: $RAW_DIR"
echo "==> Output: $OUT_DIR"

CHROME=""
if CHROME=$(find_chrome); then
  echo "==> Using headless Chrome: $CHROME"
  for shot in "${SHOTS[@]}"; do
    export_with_chrome "$CHROME" "$shot"
  done
  exit 0
fi

echo "==> Chrome not found; trying Playwright"
for shot in "${SHOTS[@]}"; do
  export_with_playwright "$shot" || {
    echo "Export failed. Install Google Chrome or run: npx playwright install chromium" >&2
    exit 1
  }
done

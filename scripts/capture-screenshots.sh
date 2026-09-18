#!/usr/bin/env bash
# Boot iPhone 16 Pro Max simulator, build/install OpenChat, and guide screenshot capture.
#
# Prerequisites (Mac + Xcode):
#   cp Config/Local.xcconfig.example Config/Local.xcconfig   # DEVELOPMENT_TEAM
#   xcodegen generate   # if project.yml changed
#
# Usage:
#   ./scripts/capture-screenshots.sh              # boot sim, build, launch, print shot guide
#   ./scripts/capture-screenshots.sh --capture 1  # save Shot 1 to screenshots/raw/shot-01.png
#   ./scripts/capture-screenshots.sh --dark       # set dark mode only (sim must be booted)
#   ./scripts/capture-screenshots.sh --light      # set light mode only
#   SIM_NAME="iPhone 15 Pro Max" ./scripts/capture-screenshots.sh
#
# Raw captures: screenshots/raw/shot-NN.png (gitignored)
# Add headline overlays per docs/launch/screenshot-guide.md before uploading to ASC.

set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="OpenChat"
PROJECT="OpenChat.xcodeproj"
SIM_NAME="${SIM_NAME:-iPhone 16 Pro Max}"
DESTINATION="platform=iOS Simulator,name=$SIM_NAME"
RAW_DIR="screenshots/raw"
BUNDLE_ID="com.genion.openchat"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script requires macOS with Xcode. Run on Robert's Mac or a connected self-hosted worker." >&2
  exit 1
fi

boot_simulator() {
  echo "==> Booting simulator: $SIM_NAME"
  xcrun simctl bootstatus "$SIM_NAME" -b >/dev/null 2>&1 || xcrun simctl boot "$SIM_NAME"
  open -a Simulator
}

set_appearance() {
  local mode="$1"
  echo "==> Setting appearance: $mode"
  xcrun simctl ui booted appearance "$mode"
}

set_status_bar() {
  echo "==> Setting status bar to 9:41 (Apple convention)"
  xcrun simctl status_bar booted override \
    --time "9:41" \
    --dataNetwork wifi \
    --wifiMode active \
    --wifiBars 3 \
    --cellularMode active \
    --cellularBars 4 \
    --batteryState charged \
    --batteryLevel 100 2>/dev/null || true
}

build_and_launch() {
  if [[ ! -f Config/Local.xcconfig ]]; then
    echo "Missing Config/Local.xcconfig — copy from Config/Local.xcconfig.example and set DEVELOPMENT_TEAM." >&2
    exit 1
  fi

  echo "==> Building OpenChat for $SIM_NAME"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -quiet build

  local settings build_dir product_name app_path
  settings=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -showBuildSettings 2>/dev/null)
  build_dir=$(echo "$settings" | awk -F'= ' '/ TARGET_BUILD_DIR /{print $2; exit}')
  product_name=$(echo "$settings" | awk -F'= ' '/ FULL_PRODUCT_NAME /{print $2; exit}')
  app_path="$build_dir/$product_name"

  echo "==> Installing and launching $BUNDLE_ID"
  xcrun simctl install booted "$app_path"
  xcrun simctl launch booted "$BUNDLE_ID" >/dev/null
}

capture_screen() {
  local shot_num="$1"
  local outfile
  mkdir -p "$RAW_DIR"
  outfile=$(printf "%s/shot-%02d.png" "$RAW_DIR" "$shot_num")
  xcrun simctl io booted screenshot "$outfile"
  echo "Saved: $outfile"
}

print_shot_guide() {
  cat <<'GUIDE'

================================================================================
OpenChat screenshot guide — follow docs/launch/screenshot-guide.md for overlays
Capture: Simulator → File → Save Screen (⌘S) OR: ./scripts/capture-screenshots.sh --capture N
Target: 6.7" 1290×2796 | iPhone 16 Pro Max sim 1320×2868 (ASC accepts both)
================================================================================

Shot 1 — Hero (DARK)
  Screen: Welcome / Connect a Provider
  Overlay: "Every model. One app."
  Manual: Delete app + reinstall for fresh state
  Capture: ./scripts/capture-screenshots.sh --capture 1

Shot 2 — Active chat (DARK)
  Prompt: "Write a Swift function that debounces a search field using Combine."
  Overlay: "Native chat with Markdown & code"
  Capture: ./scripts/capture-screenshots.sh --capture 2

Shot 3 — Model picker (LIGHT) — run --light first
  Overlay: "Switch providers without switching apps"
  Capture: ./scripts/capture-screenshots.sh --capture 3

Shot 4 — Settings → Providers (LIGHT)
  Overlay: "Your keys, your providers"
  Capture: ./scripts/capture-screenshots.sh --capture 4

Shot 5 — Web search settings (LIGHT)
  Overlay: "Optional web search, your keys"
  Capture: ./scripts/capture-screenshots.sh --capture 5

Shot 6 — Rules or memory (DARK) — run --dark first
  Overlay: "Steer behavior with rules & memory"
  Capture: ./scripts/capture-screenshots.sh --capture 6

Shot 7 — Skills + "/" menu (DARK)
  Overlay: "Reusable prompts with / commands"
  Capture: ./scripts/capture-screenshots.sh --capture 7

Shot 8 — Live Activity (DARK, optional)
  Overlay: "Replies finish in the background"
  Capture: ./scripts/capture-screenshots.sh --capture 8

After capture: add overlays → export PNG → upload per docs/launch/asc-paste-bundle.txt STEP 4
GUIDE
}

# --- argument handling ---
MODE=""
CAPTURE_NUM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dark)
      MODE="dark"
      shift
      ;;
    --light)
      MODE="light"
      shift
      ;;
    --capture)
      CAPTURE_NUM="${2:?Usage: --capture N}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$MODE" == "dark" || "$MODE" == "light" ]]; then
  boot_simulator
  set_appearance "$MODE"
  exit 0
fi

if [[ -n "$CAPTURE_NUM" ]]; then
  boot_simulator
  set_status_bar
  capture_screen "$CAPTURE_NUM"
  exit 0
fi

boot_simulator
set_status_bar
build_and_launch
set_appearance dark
print_shot_guide

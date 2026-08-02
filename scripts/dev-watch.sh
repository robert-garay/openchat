#!/usr/bin/env bash
# Builds OpenChat, installs + launches it on an iOS Simulator, then watches
# the source tree and repeats on every change (including changes that show
# up after a `git pull`). Requires Xcode command line tools + fswatch:
#
#   brew install fswatch
#
# Usage:
#   ./scripts/dev-watch.sh
#   SIM_NAME="iPhone 15" ./scripts/dev-watch.sh   # target a different simulator

set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="OpenChat"
PROJECT="OpenChat.xcodeproj"
SIM_NAME="${SIM_NAME:-iPhone 16 Pro}"
DESTINATION="platform=iOS Simulator,name=$SIM_NAME"

if ! command -v fswatch >/dev/null 2>&1; then
  echo "fswatch is required. Install it with: brew install fswatch" >&2
  exit 1
fi

xcrun simctl bootstatus "$SIM_NAME" -b >/dev/null 2>&1 || xcrun simctl boot "$SIM_NAME"
open -a Simulator

build_and_run() {
  echo "🔨 Building OpenChat…"
  if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -quiet build; then
    echo "❌ Build failed — fix the error above and save again." >&2
    return 1
  fi

  local settings build_dir product_name app_path bundle_id
  settings=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -showBuildSettings 2>/dev/null)
  build_dir=$(echo "$settings" | awk -F'= ' '/ TARGET_BUILD_DIR /{print $2; exit}')
  product_name=$(echo "$settings" | awk -F'= ' '/ FULL_PRODUCT_NAME /{print $2; exit}')
  app_path="$build_dir/$product_name"
  bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Info.plist")

  xcrun simctl install booted "$app_path"
  xcrun simctl launch booted "$bundle_id" >/dev/null
  echo "✅ Launched $bundle_id on $SIM_NAME"
}

build_and_run || true

echo "👀 Watching OpenChat/, OpenChatTests/, and project.yml for changes (Ctrl+C to stop)…"
fswatch -o OpenChat OpenChatTests project.yml | while read -r _; do
  build_and_run || true
done

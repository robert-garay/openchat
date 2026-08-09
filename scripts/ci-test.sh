#!/usr/bin/env bash
# Run the same unit-test invocation CI uses. Requires macOS + Xcode 16+.
#
# Usage:
#   ./scripts/ci-test.sh
#   SIM_NAME="iPhone 16" ./scripts/ci-test.sh
#   SKIP_XCODEGEN=1 ./scripts/ci-test.sh

set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="${SCHEME:-OpenChat}"
PROJECT="${PROJECT:-OpenChat.xcodeproj}"
RESULT_BUNDLE="${RESULT_BUNDLE:-TestResults.xcresult}"
DERIVED_DATA="${DERIVED_DATA:-DerivedData/CI}"

resolve_destination() {
  if [[ -n "${DESTINATION:-}" ]]; then
    printf '%s\n' "$DESTINATION"
    return
  fi

  if [[ -n "${SIM_NAME:-}" ]]; then
    printf 'platform=iOS Simulator,name=%s\n' "$SIM_NAME"
    return
  fi

  local device
  device="$(
    xcrun simctl list devices available 2>/dev/null \
      | sed -n 's/^[[:space:]]*\(iPhone[^()]*\) (.*/\1/p' \
      | sed 's/[[:space:]]*$//' \
      | head -n 1
  )"

  if [[ -z "$device" ]]; then
    echo "No available iPhone simulator found. Set DESTINATION or SIM_NAME." >&2
    exit 1
  fi

  printf 'platform=iOS Simulator,name=%s\n' "$device"
}

if [[ "${SKIP_XCODEGEN:-0}" != "1" ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    echo "==> Generating project with XcodeGen"
    xcodegen generate
  else
    echo "==> xcodegen not found; using committed $PROJECT"
  fi
fi

DESTINATION="$(resolve_destination)"
echo "==> Destination: $DESTINATION"
rm -rf "$RESULT_BUNDLE"

XCODEBUILD_ARGS=(
  test
  -project "$PROJECT"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA"
  -parallel-testing-enabled YES
  -enableCodeCoverage YES
  -resultBundlePath "$RESULT_BUNDLE"
  CODE_SIGN_IDENTITY="-"
  CODE_SIGNING_ALLOWED=YES
)

if command -v xcbeautify >/dev/null 2>&1; then
  set -o pipefail
  xcodebuild "${XCODEBUILD_ARGS[@]}" | xcbeautify
else
  xcodebuild "${XCODEBUILD_ARGS[@]}"
fi

echo "==> Result bundle: $RESULT_BUNDLE"

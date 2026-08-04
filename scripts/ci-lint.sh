#!/usr/bin/env bash
# Run SwiftLint the same way CI does.
#
# Usage:
#   ./scripts/ci-lint.sh
#
# Prefers a local `swiftlint` binary (brew install swiftlint). Falls back to the
# same Docker image CI uses when Docker is available.

set -euo pipefail
cd "$(dirname "$0")/.."

SWIFTLINT_IMAGE="${SWIFTLINT_IMAGE:-ghcr.io/realm/swiftlint:0.57.0}"
REPORTER_ARGS=()
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  REPORTER_ARGS=(--reporter github-actions-logging)
fi

if command -v swiftlint >/dev/null 2>&1; then
  echo "==> SwiftLint $(swiftlint version) (local)"
  # Fail on errors only for iteration 1; promote --strict once the codebase is clean.
  swiftlint lint "${REPORTER_ARGS[@]}"
  exit 0
fi

if command -v docker >/dev/null 2>&1; then
  echo "==> SwiftLint via Docker image $SWIFTLINT_IMAGE"
  docker run --rm \
    --volume "$PWD:/work" \
    --workdir /work \
    "$SWIFTLINT_IMAGE" \
    lint "${REPORTER_ARGS[@]}"
  exit 0
fi

echo "swiftlint is required. Install with: brew install swiftlint" >&2
echo "Or install Docker to use $SWIFTLINT_IMAGE" >&2
exit 1

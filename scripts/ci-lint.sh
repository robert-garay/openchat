#!/usr/bin/env bash
# Run SwiftLint the same way CI does.
#
# Usage:
#   ./scripts/ci-lint.sh

set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint is required. Install it with: brew install swiftlint" >&2
  exit 1
fi

echo "==> SwiftLint $(swiftlint version)"
# Fail on errors only for iteration 1; promote --strict once the codebase is clean.
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  swiftlint lint --reporter github-actions-logging
else
  swiftlint lint
fi

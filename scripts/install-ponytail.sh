#!/usr/bin/env bash
# Idempotent ponytail install for Cursor Cloud Agent VMs and local dev shells.
# Safe to re-run. Requires node on PATH.
#
# Default mode for hook injection: full (override with PONYTAIL_DEFAULT_MODE).

set -euo pipefail

PONYTAIL_DIR="${PONYTAIL_DIR:-$HOME/ponytail}"
PONYTAIL_REPO="https://github.com/DietrichGebert/ponytail"
export PONYTAIL_DEFAULT_MODE="${PONYTAIL_DEFAULT_MODE:-full}"

SKILLS=(
  ponytail
  ponytail-review
  ponytail-audit
  ponytail-debt
  ponytail-gain
  ponytail-help
)

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

if ! command -v node >/dev/null 2>&1; then
  fail "node is required on PATH (ponytail hooks are Node.js scripts)"
fi

if [[ ! -d "$PONYTAIL_DIR/.git" ]]; then
  echo "==> Cloning ponytail to $PONYTAIL_DIR"
  git clone "$PONYTAIL_REPO" "$PONYTAIL_DIR"
else
  echo "==> Updating ponytail at $PONYTAIL_DIR"
  git -C "$PONYTAIL_DIR" pull --ff-only
fi

echo "==> Installing Cursor hooks (PONYTAIL_DEFAULT_MODE=$PONYTAIL_DEFAULT_MODE)"
node "$PONYTAIL_DIR/scripts/cursor-hooks.js" install

link_skills() {
  local dest="$1"
  mkdir -p "$dest"
  for skill in "${SKILLS[@]}"; do
    local src="$PONYTAIL_DIR/skills/$skill"
    [[ -d "$src" ]] || fail "missing skill directory: $src"
    ln -sfn "$src" "$dest/$skill"
  done
}

echo "==> Symlinking ponytail skills"
link_skills "$HOME/.cursor/skills"
link_skills "$HOME/.agents/skills"

echo "==> ponytail install complete"

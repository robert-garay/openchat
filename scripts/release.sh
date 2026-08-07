#!/usr/bin/env bash
# Cut a new OpenChat release.
#
# Usage:
#   ./scripts/release.sh patch
#   ./scripts/release.sh minor
#   ./scripts/release.sh major
#
# The script:
#   - checks that you are on the main branch with a clean working tree,
#   - computes the next SemVer version,
#   - increments the monotonic CURRENT_PROJECT_VERSION,
#   - updates project.yml and regenerates OpenChat.xcodeproj,
#   - updates CHANGELOG.md,
#   - commits the changes,
#   - creates and pushes an annotated tag.

set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

increment() {
  local version="$1"
  local component="$2"
  local major minor patch

  IFS='.' read -r major minor patch <<< "$version"
  major="${major:-0}"
  minor="${minor:-0}"
  patch="${patch:-0}"

  case "$component" in
    major) ((major++)); minor=0; patch=0 ;;
    minor) ((minor++)); patch=0 ;;
    patch) ((patch++)) ;;
    *) fail "unknown component: $component" ;;
  esac

  echo "${major}.${minor}.${patch}"
}

component="${1:-}"
if [[ -z "$component" ]]; then
  fail "usage: $0 <patch|minor|major>"
fi
if [[ "$component" != "patch" && "$component" != "minor" && "$component" != "major" ]]; then
  fail "invalid component '$component'. Must be patch, minor, or major."
fi

command -v git >/dev/null 2>&1 || fail "git is required"
command -v xcodegen >/dev/null 2>&1 || fail "xcodegen is required (brew install xcodegen)"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$branch" != "main" ]]; then
  fail "must be on main branch (currently on '$branch')"
fi

if ! git diff-index --quiet HEAD --; then
  fail "working tree is not clean. Commit or stash changes first."
fi

if ! git pull --ff-only origin main; then
  fail "could not fast-forward main. Resolve manually before releasing."
fi

echo "==> Reading current version from project.yml"
current_version=$(python3 - <<'PY'
import re, sys
from pathlib import Path
project_path = Path("project.yml")
if not project_path.exists():
    sys.exit("project.yml not found")
for line in project_path.read_text().splitlines():
    m = re.match(r'^\s*MARKETING_VERSION:\s*"?([^"\s]+)"?', line)
    if m:
        print(m.group(1))
        sys.exit(0)
sys.exit("MARKETING_VERSION not found in project.yml")
PY
)

current_build=$(python3 - <<'PY'
import re, sys
from pathlib import Path
project_path = Path("project.yml")
for line in project_path.read_text().splitlines():
    m = re.match(r'^\s*CURRENT_PROJECT_VERSION:\s*"?([^"\s]+)"?', line)
    if m:
        print(m.group(1))
        sys.exit(0)
sys.exit("CURRENT_PROJECT_VERSION not found in project.yml")
PY
)

new_version=$(increment "$current_version" "$component")
if ! [[ "$current_build" =~ ^[0-9]+$ ]]; then
  fail "CURRENT_PROJECT_VERSION '$current_build' is not an integer"
fi
new_build=$((current_build + 1))

echo "Releasing: $current_version ($current_build) -> $new_version ($new_build)"

# Update project.yml
today=$(date +%Y-%m-%d)
python3 - "$new_version" "$new_build" <<'PY'
import re, sys
from pathlib import Path
new_version, new_build = sys.argv[1:3]
project_path = Path("project.yml")
text = project_path.read_text()
text = re.sub(
    r'^(\s*MARKETING_VERSION:\s*)"?[^"\s]+"?',
    rf'\1"{new_version}"',
    text,
    flags=re.MULTILINE,
)
text = re.sub(
    r'^(\s*CURRENT_PROJECT_VERSION:\s*)"?[^"\s]+"?',
    rf'\1"{new_build}"',
    text,
    flags=re.MULTILINE,
)
project_path.write_text(text)
PY

echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Updating CHANGELOG.md"
python3 - "$new_version" "$today" <<'PY'
import sys
from pathlib import Path

version, date = sys.argv[1:3]
changelog_path = Path("CHANGELOG.md")
text = changelog_path.read_text()

unreleased_heading = "## [Unreleased]"
unreleased_start = text.find(unreleased_heading)
if unreleased_start == -1:
    sys.exit("CHANGELOG.md missing '## [Unreleased]' section")

heading_end = unreleased_start + len(unreleased_heading)
# Find the next version heading after the Unreleased section.
next_heading = text.find("\n## [", heading_end)
if next_heading == -1:
    unreleased_body = text[heading_end:].lstrip("\n")
    tail = ""
else:
    unreleased_body = text[heading_end:next_heading].lstrip("\n")
    tail = text[next_heading:]

new_unreleased = (
    "## [Unreleased]\n\n"
    "### Added\n\n"
    "### Changed\n\n"
    "### Fixed\n\n"
    "### Deprecated\n\n"
    "### Removed\n\n"
    "### Security\n\n"
)
released_section = f"## [{version}] - {date}\n\n{unreleased_body}"

new_text = text[:unreleased_start] + new_unreleased + released_section + tail
changelog_path.write_text(new_text)
print(f"CHANGELOG.md updated for v{version}")
PY

echo "==> Committing changes"
git add project.yml OpenChat.xcodeproj CHANGELOG.md
git commit -m "chore(release): bump version to $new_version ($new_build)"

echo "==> Creating and pushing tag"
git tag -a "v$new_version" -m "Release v$new_version (build $new_build)"
git push origin main "v$new_version"

echo ""
echo "Release v$new_version (build $new_build) pushed."
echo "GitHub Actions will create a GitHub Release from the tag."

#!/usr/bin/env python3
"""Extract the release notes for a given version from CHANGELOG.md."""
import re, sys
from pathlib import Path

version = sys.argv[1]
changelog_path = Path("CHANGELOG.md")
if not changelog_path.exists():
    sys.exit("CHANGELOG.md not found")

text = changelog_path.read_text()
# Match the version heading and capture until the next top-level heading or EOF.
pattern = rf"## \[{re.escape(version)}\] - \d{{4}}-\d{{2}}-\d{{2}}\n\n(.*?)(?=\n## \[|\Z)"
match = re.search(pattern, text, re.DOTALL)
if not match:
    sys.exit(f"No changelog section found for version {version}")
section = match.group(1).strip()
if not section:
    section = "No release notes available."
print(section)

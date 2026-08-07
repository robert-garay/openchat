#!/usr/bin/env bash
# Validate CI config without macOS/Xcode. Safe to run on Linux.
#
# Usage:
#   ./scripts/validate-ci.sh

set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

echo "==> Checking required files"
for path in \
  .github/workflows/ci.yml \
  .swiftlint.yml \
  project.yml \
  scripts/ci-test.sh \
  scripts/ci-lint.sh \
  OpenChat.xcodeproj/xcshareddata/xcschemes/OpenChat.xcscheme
do
  [[ -f "$path" ]] || fail "missing $path"
done

echo "==> Checking script executability"
for path in scripts/ci-test.sh scripts/ci-lint.sh scripts/validate-ci.sh scripts/release.sh; do
  [[ -x "$path" ]] || fail "$path is not executable"
done

echo "==> Parsing YAML"
python3 - <<'PY'
from pathlib import Path
import sys

try:
    import yaml
except ImportError:
    # Minimal subset parser fallback for CI workflow structure checks.
    yaml = None

errors = []

def load(path: Path):
    text = path.read_text()
    if yaml is None:
        return text
    try:
        return yaml.safe_load(text)
    except Exception as exc:  # noqa: BLE001
        errors.append(f"{path}: {exc}")
        return None

workflow_path = Path(".github/workflows/ci.yml")
project_path = Path("project.yml")
lint_path = Path(".swiftlint.yml")

workflow = load(workflow_path)
project = load(project_path)
_ = load(lint_path)

if yaml is not None:
    if not isinstance(workflow, dict):
        errors.append("ci.yml did not parse to a mapping")
    else:
        jobs = workflow.get("jobs") or {}
        if "lint" not in jobs or "test" not in jobs:
            errors.append("ci.yml must define lint and test jobs")
        else:
            lint_runner = jobs["lint"].get("runs-on")
            test_runner = jobs["test"].get("runs-on")
            if lint_runner != "ubuntu-latest":
                errors.append(f"lint job should run on ubuntu-latest, got {lint_runner!r}")
            if test_runner != "macos-15":
                errors.append(f"test job should run on macos-15, got {test_runner!r}")
        on = workflow.get("on") or workflow.get(True)  # PyYAML may coerce 'on' -> True
        if on is None:
            errors.append("ci.yml missing on: triggers")
        concurrency = workflow.get("concurrency") or {}
        if "group" not in concurrency:
            errors.append("ci.yml missing concurrency.group")

    if not isinstance(project, dict):
        errors.append("project.yml did not parse to a mapping")
    else:
        scheme = ((project.get("schemes") or {}).get("OpenChat") or {}).get("test") or {}
        if scheme.get("gatherCoverageData") is not True:
            errors.append("project.yml OpenChat scheme must set gatherCoverageData: true")
        targets = scheme.get("targets") or []
        found = False
        for target in targets:
            if isinstance(target, dict) and target.get("name") == "OpenChatTests":
                found = True
                if target.get("parallelizable") is not True:
                    errors.append("OpenChatTests must be parallelizable: true")
                if target.get("randomExecutionOrder") is not True:
                    errors.append("OpenChatTests must set randomExecutionOrder: true")
        if not found:
            errors.append("OpenChatTests missing from scheme test targets")
else:
    text = workflow_path.read_text()
    for needle in ("jobs:", "lint:", "test:", "concurrency:", "ubuntu-latest", "macos-15", "scripts/ci-test.sh", "swiftlint"):
        if needle not in text:
            errors.append(f"ci.yml missing expected content: {needle}")
    project_text = project_path.read_text()
    for needle in ("gatherCoverageData: true", "parallelizable: true", "randomExecutionOrder: true"):
        if needle not in project_text:
            errors.append(f"project.yml missing expected content: {needle}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("YAML checks passed" + (" (PyYAML)" if yaml is not None else " (fallback)"))
PY

echo "==> Checking scheme coverage / parallel flags"
python3 - <<'PY'
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

path = Path("OpenChat.xcodeproj/xcshareddata/xcschemes/OpenChat.xcscheme")
root = ET.parse(path).getroot()
test_action = root.find("TestAction")
if test_action is None:
    sys.exit("TestAction missing from OpenChat.xcscheme")

if test_action.attrib.get("codeCoverageEnabled") != "YES":
    sys.exit("codeCoverageEnabled must be YES")

coverage = test_action.find("CodeCoverageTargets/BuildableReference")
if coverage is None or coverage.attrib.get("BlueprintName") != "OpenChat":
    sys.exit("CodeCoverageTargets must include OpenChat")

testable = test_action.find("Testables/TestableReference")
if testable is None:
    sys.exit("TestableReference missing")
if testable.attrib.get("parallelizable") != "YES":
    sys.exit("parallelizable must be YES")
if testable.attrib.get("testExecutionOrdering") != "random":
    sys.exit("testExecutionOrdering must be random")

print("Scheme flags OK")
PY

echo "==> All CI validation checks passed"

# Agent Rules for OpenChat

This file contains project-specific rules and conventions for any agent (Claude, OpenCode, Codex, etc.) working on OpenChat.

## Project overview

OpenChat is a native iOS chat app written in SwiftUI + SwiftData. The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`. No backend server, no telemetry, no third-party analytics.

## Build and test commands

```bash
xcodegen generate                # regenerate OpenChat.xcodeproj from project.yml
open OpenChat.xcodeproj          # open in Xcode
./scripts/validate-ci.sh         # validate CI config (Linux-safe)
./scripts/ci-lint.sh             # run SwiftLint locally (requires swiftlint)
./scripts/ci-test.sh             # run unit tests locally (requires Xcode 16+)
```

## Versioning rules

- **Source of truth for version:** `project.yml`.
  - `MARKETING_VERSION` — the public SemVer version (e.g. `1.0.0`).
  - `CURRENT_PROJECT_VERSION` — the monotonic integer build number used by TestFlight / App Store Connect.
- **Only** modify the version by running `scripts/release.sh <patch|minor|major>`.
  - Never edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` by hand.
  - Never rely on the `.xcodeproj` UI build settings; always change `project.yml` and regenerate.
- Do **not** run `scripts/release.sh` unless the user explicitly asks you to cut a release. The script pushes commits and tags to `origin/main`.
- **Always run `xcodegen generate`** after editing `project.yml` so the committed `.xcodeproj` stays in sync.
- The in-app version in `SettingsView` is read automatically from `Bundle.main.infoDictionary`, so it stays up-to-date as long as `project.yml` is correct.

## Release workflow

1. Ensure `main` is in a releasable state and CI is green.
2. Run `scripts/release.sh patch|minor|major` from the `main` branch.
   - The script updates `project.yml`, regenerates `.xcodeproj`, updates `CHANGELOG.md`, commits, and pushes an annotated Git tag.
3. The GitHub Actions release workflow triggers on the tag and creates a GitHub Release with the matching `CHANGELOG.md` section.
4. Upload the build to App Store Connect / TestFlight manually or via a future Fastlane workflow.

## Branch and pull request rules

- `main` is protected. All code changes must land via a pull request.
- Agents must create a branch, push it, and open a PR against `main`. Do not commit directly to `main`.
- Open a PR against `main`; CI (lint + tests) must pass before merging.
- For now, releases are cut directly from `main`. Release branches will be introduced later.
- Each notable PR should add a bullet under the `[Unreleased]` section of `CHANGELOG.md` in the appropriate category (`Added`, `Changed`, `Fixed`, `Deprecated`, `Removed`, `Security`).

## CHANGELOG rules

- Follow [Keep a Changelog](https://keepachangelog.com/) format.
- Use the categories: `Added`, `Changed`, `Fixed`, `Deprecated`, `Removed`, `Security`.
- Keep a top-level `[Unreleased]` section.
- When a release is created, the release script will rename `[Unreleased]` to the new version and date and add a fresh empty `[Unreleased]` section.

## Code and file conventions

- Swift version: `6.0`. iOS deployment target: `17.0`.
- Use `Bundle.main.infoDictionary` for the version string in UI; do not hard-code the version in Swift source.
- Do not commit `Config/Local.xcconfig` (it is gitignored). Use `Config/Local.xcconfig.example` as a template.
- Prefer minimal changes. Do not add dependencies or heavy tooling unless explicitly asked.
- Do not add emojis to source files unless explicitly requested.
- Do not create documentation files unless explicitly requested by the user.

## When making changes

1. Read the relevant code first (`OpenChat/`, `OpenChatTests/`, `project.yml`, `.github/workflows/`).
2. Make the minimal change that solves the task.
3. Run the relevant scripts (`validate-ci.sh`, `ci-lint.sh`, `ci-test.sh`) if they are applicable and available.
4. If you touch `project.yml`, run `xcodegen generate` and include the regenerated `.xcodeproj` in the same commit.
5. If you touch a feature, add or update a `CHANGELOG.md` bullet under `[Unreleased]` if the change is user-facing.

## Ponytail

Cloud Agents do not run Cursor `sessionStart` hooks, so this section carries the ponytail ruleset. Local IDE sessions get the same rules via hooks installed by `scripts/install-ponytail.sh` (default mode: `full`).

You are a lazy senior developer. Lazy means efficient, not careless. The best code is the code never written.

Before writing any code, stop at the first rung that holds:

1. Does this need to be built at all? (YAGNI)
2. Does it already exist in this codebase? Reuse the helper, util, or pattern that's already here.
3. Does the standard library already do this? Use it.
4. Does a native platform feature cover it? Use it.
5. Does an already-installed dependency solve it? Use it.
6. Can this be one line? Make it one line.
7. Only then: write the minimum code that works.

The ladder runs after you understand the problem, not instead of it: read the task and the code it touches, trace the real flow end to end, then climb.

Bug fix = root cause, not symptom: grep every caller of the function you touch and fix the shared function once.

Rules:

- No abstractions that weren't explicitly requested.
- No new dependency if it can be avoided.
- No boilerplate nobody asked for.
- Deletion over addition. Boring over clever. Fewest files possible.
- Shortest working diff wins, but only once you understand the problem.
- Question complex requests: "Do you actually need X, or does Y cover it?"
- Mark deliberate simplifications with a `ponytail:` comment naming the ceiling and upgrade path.

Not lazy about: understanding the problem, input validation at trust boundaries, error handling that prevents data loss, security, accessibility, calibration real hardware needs, anything explicitly requested. Non-trivial logic leaves one runnable check behind (assert-based demo or one small test file; no frameworks). Trivial one-liners need no test.

Do not add `.cursor/rules/ponytail.mdc` — it conflicts with ponytail hooks. Skills: `/ponytail`, `/ponytail-review`, `/ponytail-audit`, `/ponytail-debt`, `/ponytail-gain`, `/ponytail-help`.

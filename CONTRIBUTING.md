# Contributing to OpenChat

## Requirements

- macOS with Xcode 16+
- An Apple Developer account (free is enough to run on your own device; a paid account is required for TestFlight)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```bash
xcodegen generate      # regenerates OpenChat.xcodeproj from project.yml
open OpenChat.xcodeproj
```

The `.xcodeproj` is committed to the repo, so you can also just open it directly — only re-run `xcodegen generate` after pulling changes to `project.yml` or adding/removing files.

Signing defaults to bundle id `com.genion.openchat`. Set your Apple Team ID once by copying `Config/Local.xcconfig.example` → `Config/Local.xcconfig` (gitignored) and filling in `DEVELOPMENT_TEAM`.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs SwiftLint and unit tests on every PR / push to `main`.

```bash
./scripts/validate-ci.sh   # config checks (Linux-safe)
./scripts/ci-lint.sh       # SwiftLint (macOS; brew install swiftlint)
./scripts/ci-test.sh       # xcodebuild test + coverage (macOS + Xcode 16+)
```

## Project layout

```
OpenChat/
  App/            App entry point
  Models/         Provider/model catalog, SwiftData models (Conversation, ChatMessage)
  Services/       Networking (OpenAI-compatible + Anthropic streaming clients), Keychain, ProviderStore
  Features/       Onboarding, Chat, Chat List, Settings — one folder per screen
  DesignSystem/   Shared colors, spacing, animation, haptics
OpenChatTests/    Unit tests for the provider catalog, Keychain, SSE parsing, and provider storage
```

## Pull requests

`main` is protected — all changes land via PR. Open a PR against `main`; CI (lint + tests) must pass before merge.

Add a bullet under the `[Unreleased]` section of `CHANGELOG.md` if your PR is user-facing. Use the categories from [Keep a Changelog](https://keepachangelog.com/): `Added`, `Changed`, `Fixed`, `Deprecated`, `Removed`, `Security`.

## Versioning

Version information lives in `project.yml` only:

- `MARKETING_VERSION` — public SemVer version (e.g. `1.0.0`).
- `CURRENT_PROJECT_VERSION` — monotonic integer build number for App Store Connect / TestFlight.

Never edit these values by hand. Use `scripts/release.sh` to bump them.

## Shipping to TestFlight

(Maintainers only)

1. Make sure `main` is green and you are on the `main` branch.
2. Run the release script:

   ```bash
   ./scripts/release.sh patch   # or minor / major
   ```

   This updates `project.yml`, regenerates `OpenChat.xcodeproj`, updates `CHANGELOG.md`, commits the changes, and pushes an annotated tag. GitHub Actions then creates a GitHub Release from the matching `CHANGELOG.md` section.

3. In Xcode: **Product → Archive** (requires a physical device or "Any iOS Device" build target, not the simulator).
4. In the Organizer window that opens, select the archive → **Distribute App → App Store Connect → Upload**.
5. In [App Store Connect](https://appstoreconnect.apple.com), create the app record (if it doesn't exist yet) matching your bundle ID, then open **TestFlight** for that app once the build finishes processing.
6. Add yourself (and other testers) under **Internal Testing**, attach the build, and install via the TestFlight app.

The release script already incremented `CURRENT_PROJECT_VERSION`, so App Store Connect will not reject the upload for a duplicate build number.

# Fastlane

Mac-only App Store Connect automation for OpenChat. Requires [fastlane](https://fastlane.tools) and API key auth (see `.env.example`).

```bash
cp fastlane/.env.example fastlane/.env   # fill Team ID + ASC API key
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

## Lanes

| Lane | Purpose |
|---|---|
| `beta` | Build Release IPA and upload to TestFlight |
| `sync_metadata` | Upload `fastlane/metadata/` text (description, URLs, keywords) — no binary, no screenshots |
| `upload_screenshots` | Upload `fastlane/screenshots/` — metadata unchanged |
| `submit_app` | Submit for App Review after build, metadata, and screenshots are on ASC |

## Submit for review

1. Upload build: `bundle exec fastlane beta` (or Xcode archive upload).
2. Sync metadata: `bundle exec fastlane sync_metadata`
3. Capture and upload screenshots: `./scripts/capture-screenshots.sh`, `./scripts/compose-screenshots/compose.sh`, copy finals to `fastlane/screenshots/en-US/`, then `bundle exec fastlane upload_screenshots`
4. Fill `fastlane/metadata/review_information/phone_number.txt` (required by ASC).
5. Submit: `bundle exec fastlane submit_app`

`submit_app` runs `deliver` with `skip_binary_upload`, `force`, `submit_for_review: true`, and `automatic_release: false`. App Review contact info is read from `fastlane/metadata/review_information/` when present.

Metadata source of truth for copy edits: `docs/launch/asc-paste-bundle.txt` and `docs/launch/app-review-notes.txt`.

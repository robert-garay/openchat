# OpenChat App Store Launch — Execution Checklist

Step-by-step checklist for Robert (Mac + Apple Developer) or a cloud agent with a connected self-hosted worker. Do **not** run `scripts/release.sh` unless cutting a version bump — current version is **1.1.0 (build 3)** per `project.yml`.

**Reference docs:** [`docs/app-store-metadata.md`](../app-store-metadata.md) · [`asc-paste-bundle.txt`](asc-paste-bundle.txt) · [`app-review-notes.txt`](app-review-notes.txt) · [`screenshot-guide.md`](screenshot-guide.md) · Mac runbook in Project store `docs/mac-launch-runbook.md`

---

## Phase A — Cloud-ready (complete in repo)

- [x] Landing page live: https://robert-garay.github.io/openchat/
- [x] Privacy policy live: https://robert-garay.github.io/openchat/privacy-policy.html
- [x] App Store metadata draft: `docs/app-store-metadata.md`
- [x] ASC paste bundle: `docs/launch/asc-paste-bundle.txt`
- [x] App Review notes (Option A + B): `docs/launch/app-review-notes.txt`
- [x] Screenshot guide: `docs/launch/screenshot-guide.md`
- [x] Screenshot script: `scripts/capture-screenshots.sh`
- [x] Fastlane skeleton: `fastlane/Fastfile`, `fastlane/Appfile`, `fastlane/.env.example`
- [x] Mac runbook: Project store `docs/mac-launch-runbook.md`

---

## Phase B — Mac setup (Robert or self-hosted worker)

### B1. Signing & credentials

- [ ] Copy `Config/Local.xcconfig.example` → `Config/Local.xcconfig`
- [ ] Set `DEVELOPMENT_TEAM` to your 10-character Apple Team ID
- [ ] Confirm bundle IDs in Xcode: `com.genion.openchat`, `com.genion.openchat.liveactivity`
- [ ] (Optional) Copy `fastlane/.env.example` → `fastlane/.env` and fill Apple ID + Team ID
- [ ] (Optional) Create App Store Connect API key (.p8) for headless upload

### B2. Build verification

- [ ] `xcodegen generate` (if needed after pull)
- [ ] Open `OpenChat.xcodeproj` → select **Any iOS Device (arm64)**
- [ ] Product → Build (Release) — confirm zero errors
- [ ] `./scripts/ci-test.sh` — unit tests pass

---

## Phase C — Archive & upload

- [ ] Product → **Archive** (Release, not Simulator)
- [ ] Organizer → **Distribute App** → App Store Connect → Upload
- [ ] Answer export compliance: **Yes** encryption → **Yes** exempt (standard HTTPS only)
- [ ] Wait for build processing in ASC (typically 5–30 min)
- [ ] **Alternative:** `bundle exec fastlane beta` (after configuring `fastlane/.env`)

---

## Phase D — App Store Connect record

### D1. Create app (one-time)

- [ ] ASC → Apps → **+** → New App
- [ ] Paste fields from `asc-paste-bundle.txt` **STEP 0**

### D2. App Information

- [ ] Paste **STEP 1** (name, subtitle, categories, copyright)

### D3. Pricing

- [ ] Paste **STEP 2** (Free, all territories)

### D4. Version metadata (1.1.0)

- [ ] Paste **STEP 3** (description, keywords, URLs, promotional text)
- [ ] Fill App Review contact phone in **STEP 5**

### D5. App Review notes

- [ ] Choose **Option A** (reviewer own key) or **Option B** (paste test key) in `app-review-notes.txt`
- [ ] Paste finalized notes into ASC → App Review Information → Notes

### D6. Privacy & compliance

- [ ] Complete App Privacy questionnaire per **STEP 6**
- [ ] Complete Age Rating per **STEP 7**
- [ ] Confirm export compliance per **STEP 8**

---

## Phase E — Screenshots

- [ ] Run `./scripts/capture-screenshots.sh` on Mac
- [ ] Capture shots 1–7 (optional 8) per on-screen guide
- [ ] Add headline overlays per `screenshot-guide.md`
- [ ] Export PNG at 1290×2796 (6.7") minimum
- [ ] Upload to ASC in order per **STEP 4**
- [ ] (If shipping iPad) Capture 12.9" iPad Pro screenshots

---

## Phase F — TestFlight

- [ ] ASC → TestFlight → select processed build 3
- [ ] **Internal testing:** add yourself, install via TestFlight app, smoke test
- [ ] Fix any blockers → new archive if needed (increment build in `project.yml` or via release script)
- [ ] **External testing** (optional): add beta group, short "What to Test" blurb from `testflight-invite.md`
- [ ] External review (if external group) — usually quick for BYOK apps

---

## Phase G — Submit for review

- [ ] All metadata, screenshots, privacy, age rating complete
- [ ] Build 3 attached to version 1.1.0
- [ ] App Review notes finalized (Option A or B)
- [ ] Release option: **Manually release this version**
- [ ] Click **Submit for Review**
- [ ] Monitor Resolution Center for Apple questions

---

## Phase H — Post-approval launch (same day or scheduled)

- [ ] Release manually when ready (or set availability date)
- [ ] Post launch copy from `docs/launch/` (PH, HN, social — per Robert's schedule)
- [ ] Revoke Option B test API key if used
- [ ] Optional: submit `apple-editorial-nomination.md`

---

## Cloud agent continuation

When Robert connects a self-hosted worker (`cursor worker start` on his Mac):

- [ ] Agent can run `./scripts/capture-screenshots.sh`, `./scripts/ci-test.sh`, `fastlane beta`
- [ ] Agent **cannot** complete ASC web UI steps or Apple ID login without Robert's session
- [ ] Agent **cannot** Archive/upload without signing credentials in `Local.xcconfig`

---

## Cannot complete without Mac + Apple login

| Step | Blocker |
|---|---|
| Archive & upload | Requires Xcode + valid signing + Apple Developer membership |
| Screenshot capture | Requires iOS Simulator (macOS) |
| ASC app creation & metadata paste | Requires App Store Connect web login |
| TestFlight install | Requires physical device + TestFlight app |
| Submit for review | Requires ASC account holder or Admin |

Do not mark upload/submit steps complete until Robert confirms on Mac.

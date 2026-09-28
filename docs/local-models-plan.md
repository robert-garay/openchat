# On-device open models — implementation plan

**OpenChat** · iOS 17+ · SwiftUI + SwiftData · target: curated downloads + local inference (no cloud API key).

## Current architecture (as of exploration)

| Area | Location | Notes |
|------|----------|--------|
| First-launch gate | `RootView` | Shows `WelcomeView` while `providerStore.enabledProviders.isEmpty`. |
| Onboarding CTA | `WelcomeView` | Single primary action → `AddProviderView` (templates + **Custom Endpoint** for Ollama/LM Studio). |
| Provider model | `ConfiguredProvider` + `ProviderTemplate` | Persisted JSON + Keychain; `requiresAPIKey` supports keyless local servers. |
| Model catalogs | `ProviderStore` + `ProviderModelsClient` / OpenRouter | Live `/v1/models` fetch; static lists on custom endpoints. |
| Chat routing | `ChatService.client(for: APIFormat)` → `OpenAICompatibleClient` / `AnthropicClient` | `BackgroundGenerationService` + `ChatViewModel` always HTTP `streamReply`. |
| Tools / voice | Same provider + model selection | Voice and tools assume remote APIs today. |

**Gap:** No inference backend, no local model storage, no download manager, no `APIFormat` branch for on-device MLX.

---

## 2026 iOS stack options (realistic)

| Stack | Fit | Pros | Cons |
|-------|-----|------|------|
| **mlx-swift-lm** (SPM) | **Recommended v1** | Apple Silicon Metal, HF hub helpers, `ChatSession`, streaming, tool calling, wired-memory helpers; official MLXChatExample on iOS. | Large binary + compile time; **no Simulator inference** (device-only); memory hungry; SPM links MLX into app (~size). |
| **llama.cpp** (Metal build) | Alternative | Mature GGUF ecosystem, smaller Swift bridge surface if wrapped thinly. | Custom build pipeline, tokenizer/chat template parity, maintenance burden vs mlx-swift-lm. |
| **Core ML converted models** | Secondary / niche | On-device ANE where applicable. | Conversion friction, fewer “chat-ready” OSS checkpoints, less flexible than MLX for research models. |
| **Apple Foundation Models + MLX bridge** (`MLXFoundationModels`) | Future (OS 27+) | Unified `LanguageModelSession`, guided generation. | Requires **iOS 27 SDK**; ties v2 to OS version; not a substitute for iOS 17–26 users. |
| **Apple Intelligence on-device only** | Not v1 | Zero download for supported devices. | Not user-selectable OSS catalog; licensing/API unlike “download Llama/Qwen”. |

### Device & platform constraints

- **RAM:** Plan for **6–8 GB+** devices for 1–3B Q4; 8B Q4 needs high-end phones (8 GB+) and aggressive KV limits; document “not supported” tiers.
- **Storage:** Models live in `Application Support/LocalModels/` (not iCloud backup by default); 1B ≈ 0.7–1.2 GB, 3B Q4 ≈ 2–2.5 GB. Show **honest size** before download; require Wi‑Fi option (default on cellular).
- **Thermal / battery:** Long runs heat-throttle; no background *inference* (only download); align with existing `BackgroundGenerationService` (foreground generation).
- **App Store (2.5.2):** Downloaded ML weights are allowed when from **curated, checksum-verified** sources you control; no arbitrary user-supplied URLs in v1. No executable code in model blobs.
- **Background download:** `URLSessionConfiguration.background(withIdentifier:)` + `BGTaskScheduler` for resume; **foreground** download OK for MVP with `URLSession.downloadTask` + progress from delegate (real bytes, not fake).
- **Privacy:** On-device path = no model traffic to OpenChat servers; optional HF CDN only for listed artifacts.

---

## Trusted sources (v1)

**Approach:** Curated **signed manifest** shipped with the app (or fetched from a pinned GitHub Pages URL with embedded Ed25519 public key or Apple code signature on manifest).

```json
{
  "version": 1,
  "models": [
    {
      "id": "mlx-community/Llama-3.2-1B-Instruct-4bit",
      "displayName": "Llama 3.2 1B (4-bit)",
      "bytes": 734003200,
      "sha256": "...",
      "files": [{ "path": "weights.safetensors", "url": "https://huggingface.co/...", "sha256": "..." }],
      "minRAMGB": 6,
      "backend": "mlx",
      "chatTemplate": "llama3"
    }
  ]
}
```

- **v1:** Only models in manifest; URLs are **allowlisted hostnames** (`huggingface.co`, `cdn-lfs.huggingface.co`, future mirror).
- **Verify:** SHA-256 per file + total bundle; reject on mismatch; quarantine incomplete downloads.
- **Updates:** Manifest version bump in app release; optional lightweight manifest fetch with **min app version** field.
- **Out of scope v1:** User paste of arbitrary GGUF URL, torrents, unverified HF repos.

---

## Recommended v1 model list (small, quantized)

| Model | Role | ~Size | Min device |
|-------|------|-------|------------|
| `mlx-community/Llama-3.2-1B-Instruct-4bit` | Default fast chat | ~0.8 GB | 6 GB RAM |
| `mlx-community/Qwen2.5-1.5B-Instruct-4bit` | Alt quality/speed | ~1.0 GB | 6 GB RAM |
| `mlx-community/Phi-3.5-mini-instruct-4bit` | Tight context, good instruction | ~2.0 GB | 8 GB RAM |

Optional v1.1: **3B class** (e.g. Qwen2.5-3B-4bit) gated behind “High memory” warning.

---

## Data model & API changes

1. **`InferenceBackend`** (new): `remoteHTTP` | `localMLX` (future: `foundationModels`).
2. **`ConfiguredProvider`** (extend): `inferenceBackend`, `localModelID: String?` when backend is local; `requiresAPIKey == false` for on-device.
3. **`LocalModelRecord`** (SwiftData or JSON in Application Support): `modelID`, `installState` (notInstalled / downloading / ready / failed), `installedAt`, `bytesOnDisk`, `manifestVersion`.
4. **`ProviderStore`**: `static let onDeviceProviderID = "openchat-ondevice"`; synthetic provider when ≥1 model `ready`; models list from manifest + install state (not `/v1/models`).
5. **`APIFormat`**: add `.localMLX` **or** keep `openAI` unused for local and branch earlier on `inferenceBackend` (prefer **backend enum** over overloading `APIFormat`).
6. **`ChatCompletionClient`**: `LocalMLXClient: ChatCompletionClient` — streams tokens from `ChatSession`; ignores `baseURL`/`apiKey`; maps `ChatTurn` → MLX messages; **disable tools** until MLX tool loop parity verified.
7. **`ChatService.client`**: switch on `InferenceBackend` first, then `APIFormat`.

---

## Onboarding UX (text wireframe)

```
┌─────────────────────────────────────┐
│           [OpenChat logo]           │
│         Chat with any model         │
│         (feature bullets…)          │
│                                     │
│  ┌───────────────────────────────┐  │
│  │     Connect a Provider        │  │  ← existing (cloud BYOK)
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │  Run Models on This Device    │  │  ← NEW (Phase 0 → Coming soon)
│  └───────────────────────────────┘  │
│     Custom endpoint? Add later in   │
│     Settings (Ollama on LAN…)       │
└─────────────────────────────────────┘

Sheet: "On-device models"
  • Bullets: private, offline after download, storage/RAM
  • Status: "Coming in a future update" (Phase 0)
  • [ ] Notify when available (optional AppStorage flag)
  • Link: manifest/docs on GitHub (trust transparency)
  • Dismiss
```

Post-MVP flow: same entry → **model picker** → download with real progress → registers `openchat-ondevice` provider → main chat.

---

## Phases

### Phase 0 — Onboarding intent (this PR)

- Third Welcome CTA + honest coming-soon sheet (no fake chat, no fake progress).
- Optional `@AppStorage` interest flag for future manifest ping (local only).
- CHANGELOG `[Unreleased]`.

### Phase 1 — Manifest + download

- Bundle `local-models-manifest.json`; `LocalModelDownloadService` (verify SHA-256, resume).
- Settings subsection or dedicated **On-Device Models** list (install / delete / storage used).
- Unit tests: manifest parse, checksum failure paths.

### Phase 2 — MLX runtime

- SPM: `mlx-swift` + `mlx-swift-lm` (pin revisions; document device-only CI).
- `LocalMLXClient` + `ModelContainer` lifecycle (load/unload on memory warning).
- Wire `BackgroundGenerationService` / `ChatViewModel` to local client; cap context length.

### Phase 3 — Product polish

- Device capability gate (`ProcessInfo.physicalMemory`).
- Wi‑Fi-only downloads default; thermal warning copy.
- Voice: off or local STT only until local TTS path exists.
- Tools: enable when MLX tool loop tested.

### Phase 4 — Optional

- Foundation Models bridge on iOS 27+.
- Mirror manifest on GitHub Pages; in-app update check.

---

## Smallest shippable MVP (end-to-end)

**One model** (Llama 3.2 1B 4-bit), **one path**: Welcome → download → chat with streaming. No tools, no voice, no multi-model picker beyond default. Remote providers unchanged.

---

## Risks

| Risk | Mitigation |
|------|------------|
| App size + review scrutiny | Lazy MLX SPM; document ML use in App Review notes; download weights after install. |
| OOM on older phones | Hard gate on `physicalMemory`; kill switch per model `minRAMGB`. |
| Simulator CI gap | MLX tests behind `#if targetEnvironment(simulator)` skips; device manual QA matrix. |
| Hugging Face rate limits / ToS | Pin CDN URLs in manifest; consider self-hosted mirror in repo org. |
| Dual routing complexity | Single `InferenceBackend` switch at client factory; one synthetic provider ID. |
| User expects OpenRouter-quality from 1B | Onboarding copy sets expectations; show model card (params, quant, context). |

---

## Dependency justification (Phase 2+)

- **mlx-swift-lm:** Only maintained Swift-native path with HF load + chat session aligned with Apple Silicon; avoids maintaining llama.cpp Metal fork.
- No new deps for Phase 0–1.

---

## Phase 0 code touchpoints

- `OpenChat/Features/Onboarding/WelcomeView.swift`
- `OpenChat/Features/Onboarding/LocalModelsOnboardingView.swift` (new sheet)
- `CHANGELOG.md`

**Not yet:** `ProviderStore` stub provider (would satisfy `enabledProviders` and break chat) — defer until `LocalMLXClient` exists.

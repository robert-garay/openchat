# Local models manifest specification

**OpenChat** ships a curated, checksum-verified catalog of on-device MLX weights. Phase 1 consumes this schema; Phase 0 only documents it.

**User-facing picks:** See Project store [`local-models-recommendations.md`](/cursor/stores/self/docs/local-models-recommendations.md) (mirrored rationale in repo planning docs).

---

## Top-level object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | integer | yes | Manifest schema / content version; bump when entries change |
| `minAppVersion` | string | no | SemVer floor (e.g. `"1.2.0"`) for optional remote manifest fetch |
| `models` | array | yes | Curated model entries (see below) |

---

## Model entry

Each element of `models` describes one downloadable MLX bundle.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Stable OpenChat id (often equals `mlxModelID`) |
| `mlxModelID` | string | yes | Hugging Face repo id, e.g. `mlx-community/Llama-3.2-1B-Instruct-4bit` |
| `displayName` | string | yes | User-visible name in picker |
| `tier` | string | yes | Device RAM tier this row targets: `legacy4`, `standard6`, `performance8`, `high12` |
| `intelligenceLevel` | string | yes | `quick` \| `everyday` \| `best` (maps to onboarding copy) |
| `minRAMGB` | integer | yes | Minimum **physical** RAM (GB) to allow download / load |
| `recommendedDevices` | string[] | yes | Human-readable labels, e.g. `"iPhone 15 (6 GB)"`, `"iPhone 16 Pro (8 GB)"` |
| `bytes` | integer | yes | Total download size in bytes (sum of verified files) |
| `sha256` | string | yes | SHA-256 hex of **complete bundle** after download & merge (placeholder until pinned in CI) |
| `backend` | string | yes | `"mlx"` for v1 |
| `chatTemplate` | string | yes | Template key consumed by mlx-swift-lm loader (`llama3`, `qwen2`, `phi3`, …) |
| `files` | array | yes | Per-file download descriptors (see below) |
| `defaultForTier` | boolean | no | If true, pre-select in onboarding for matching `tier` + `intelligenceLevel` |
| `notRecommendedReason` | string | no | When present, show in catalog but block download (education / denylist) |

### `files[]` entry

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | yes | Relative path inside model directory |
| `url` | string | yes | HTTPS URL; host must be allowlisted (`huggingface.co`, `cdn-lfs.huggingface.co`, future mirror) |
| `sha256` | string | yes | SHA-256 hex of this file |
| `bytes` | integer | no | Size for progress UI |

---

## Validation rules (app)

1. Reject unknown hosts; require HTTPS.
2. Verify each file `sha256` after download; verify bundle `sha256` before marking install `ready`.
3. Hide or disable entries where `ProcessInfo.processInfo.physicalMemory` &lt; `minRAMGB * 1024^3` (use same thresholds as `LocalModelRecommendation`).
4. Only one `defaultForTier: true` per (`tier`, `intelligenceLevel`) pair.

---

## Example manifest snippet

Sizes are **Hugging Face safetensors totals** (2026-03-28). Replace `sha256` placeholders before release.

```json
{
  "version": 1,
  "minAppVersion": "1.2.0",
  "models": [
    {
      "id": "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
      "mlxModelID": "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
      "displayName": "Qwen 2.5 0.5B (4-bit)",
      "tier": "legacy4",
      "intelligenceLevel": "quick",
      "minRAMGB": 4,
      "recommendedDevices": ["iPhone 12 / 13 mini (4 GB class)"],
      "bytes": 494032768,
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "backend": "mlx",
      "chatTemplate": "qwen2",
      "defaultForTier": true,
      "files": [
        {
          "path": "model.safetensors",
          "url": "https://huggingface.co/mlx-community/Qwen2.5-0.5B-Instruct-4bit/resolve/main/model.safetensors",
          "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
        }
      ]
    },
    {
      "id": "mlx-community/Qwen3-0.6B-4bit",
      "mlxModelID": "mlx-community/Qwen3-0.6B-4bit",
      "displayName": "Qwen 3 0.6B (4-bit)",
      "tier": "legacy4",
      "intelligenceLevel": "quick",
      "minRAMGB": 4,
      "recommendedDevices": ["iPhone 12 / 13 mini (4 GB class)"],
      "bytes": 596049920,
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "backend": "mlx",
      "chatTemplate": "qwen3",
      "files": []
    },
    {
      "id": "mlx-community/Llama-3.2-1B-Instruct-4bit",
      "mlxModelID": "mlx-community/Llama-3.2-1B-Instruct-4bit",
      "displayName": "Llama 3.2 1B (4-bit)",
      "tier": "standard6",
      "intelligenceLevel": "quick",
      "minRAMGB": 6,
      "recommendedDevices": ["iPhone 13–15 / 15 Plus (6 GB)"],
      "bytes": 1235814400,
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "backend": "mlx",
      "chatTemplate": "llama3",
      "defaultForTier": true,
      "files": []
    },
    {
      "id": "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
      "mlxModelID": "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
      "displayName": "Qwen 2.5 1.5B (4-bit)",
      "tier": "standard6",
      "intelligenceLevel": "everyday",
      "minRAMGB": 6,
      "recommendedDevices": ["iPhone 13–15 / 15 Plus (6 GB)"],
      "bytes": 1543714304,
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "backend": "mlx",
      "chatTemplate": "qwen2",
      "defaultForTier": true,
      "files": []
    },
    {
      "id": "mlx-community/Phi-3.5-mini-instruct-4bit",
      "mlxModelID": "mlx-community/Phi-3.5-mini-instruct-4bit",
      "displayName": "Phi-3.5 mini (4-bit)",
      "tier": "performance8",
      "intelligenceLevel": "everyday",
      "minRAMGB": 8,
      "recommendedDevices": ["iPhone 15 Pro+", iPhone 16 series (8 GB)"],
      "bytes": 3821079552,
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "backend": "mlx",
      "chatTemplate": "phi3",
      "files": []
    },
    {
      "id": "mlx-community/Qwen2.5-3B-Instruct-4bit",
      "mlxModelID": "mlx-community/Qwen2.5-3B-Instruct-4bit",
      "displayName": "Qwen 2.5 3B (4-bit)",
      "tier": "performance8",
      "intelligenceLevel": "best",
      "minRAMGB": 8,
      "recommendedDevices": ["iPhone 15 Pro+, iPhone 16 series (8 GB)"],
      "bytes": 3085938688,
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "backend": "mlx",
      "chatTemplate": "qwen2",
      "defaultForTier": true,
      "files": []
    },
    {
      "id": "mlx-community/Qwen3-4B-Instruct-2507-4bit",
      "mlxModelID": "mlx-community/Qwen3-4B-Instruct-2507-4bit",
      "displayName": "Qwen 3 4B (4-bit)",
      "tier": "performance8",
      "intelligenceLevel": "best",
      "minRAMGB": 8,
      "recommendedDevices": ["iPhone 15 Pro+, iPhone 16 series (8 GB)"],
      "bytes": 4022468096,
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "backend": "mlx",
      "chatTemplate": "qwen3",
      "files": []
    },
    {
      "id": "mlx-community/Llama-3.1-8B-Instruct-4bit",
      "mlxModelID": "mlx-community/Llama-3.1-8B-Instruct-4bit",
      "displayName": "Llama 3.1 8B (4-bit)",
      "tier": "performance8",
      "intelligenceLevel": "best",
      "minRAMGB": 12,
      "recommendedDevices": [],
      "bytes": 8030261248,
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "backend": "mlx",
      "chatTemplate": "llama3",
      "notRecommendedReason": "Too large for reliable on-phone chat; use cloud or Mac.",
      "files": []
    }
  ]
}
```

**Note:** Duplicate `mlxModelID` with distinct `id` (e.g. same 1.5B for `everyday` and `best` on 6 GB) is optional; Phase 1 may collapse to one row and map multiple intelligence levels in app logic (`LocalModelRecommendation`).

---

## Swift reference

Pure selection logic lives in `OpenChat/Services/LocalModelRecommendation.swift` (no MLX dependency). Unit tests: `OpenChatTests/LocalModelRecommendationTests.swift`.

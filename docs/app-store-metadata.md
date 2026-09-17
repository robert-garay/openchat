# App Store Connect Metadata (Draft)

Copy/paste drafts for OpenChat 1.x App Store submission. Update version numbers and URLs if they change before submit.

## Basic information

| Field | Value |
|---|---|
| **App name** | OpenChat |
| **Subtitle** (30 chars max) | Every major LLM, one app |
| **Bundle ID** | `com.genion.openchat` |
| **Primary category** | Productivity |
| **Secondary category** | Utilities |
| **Copyright** | © 2026 Robert Garay |
| **Support URL** | https://github.com/robert-garay/openchat/issues |
| **Privacy Policy URL** | https://robert-garay.github.io/openchat/privacy-policy.html |
| **Marketing URL** (optional) | https://github.com/robert-garay/openchat |

## Promotional text (170 chars, editable without new build)

Chat with OpenAI, Claude, Gemini, OpenRouter, and your own endpoints from one native iOS app. BYOK, on-device history, web search, rules, memory, and skills.

## Description

OpenChat is the native iOS home for every major LLM.

Connect your own API keys and chat with OpenAI, Anthropic, Google Gemini, OpenRouter, Mistral, DeepSeek, Qwen, Kimi, Z.ai, 01.AI, or any OpenAI-compatible endpoint (Ollama, LM Studio, vLLM, internal gateways) from one clean interface.

**Why OpenChat**
- One workflow across providers — switch models without changing apps
- Live model catalogs from supported providers
- Bring your own key (BYOK) — no OpenChat account, no backend
- Chats, rules, memory, and skills stay on your device

**Features**
- Multi-provider chat with streaming Markdown, tables, and syntax-highlighted code
- Web search via Tavily, Exa, Brave, Serper, or SerpAPI (your keys)
- Global and per-chat rules; editable memory; slash-command skills (beta)
- Image attachments for vision models; background replies with Live Activity and local notification when complete
- Compact context mode and light/dark appearance

OpenChat does not include ads or analytics SDKs. When you send a message, data goes directly from your device to the AI or search provider you configured, under that provider’s terms.

Questions: open an issue on GitHub or email robert@genion.ai.

## Keywords (100 chars, comma-separated, no spaces after commas)

openai,claude,gemini,chatgpt,llm,openrouter,byok,ai chat,markdown,ollama

## Age rating (questionnaire guidance)

Answer honestly in App Store Connect. Suggested baseline for a BYOK AI chat client:

| Topic | Suggested answer | Notes |
|---|---|---|
| Unrestricted web access | **No** | App calls configured APIs; no general browser |
| User-generated content | **Yes** (if prompted) | User types prompts; no public social feed in app |
| Mature/suggestive themes | **Infrequent/Mild** or per Apple wizard | Depends on model output; generative AI may produce varied content |
| Gambling, violence, etc. | **None** | Not applicable unless tools surface such content |
| Made for Kids | **No** | BYOK AI client |

Apple may classify generative-AI apps with additional questions; disclose that output depends on third-party models the user selects.

## App Privacy (Privacy Nutrition Labels)

**Data linked to you:** None collected by the developer (OpenChat has no backend).

**Data not linked to you:** None collected by the developer.

**Data used to track you:** None.

**Developer data collection:** Select **No, we do not collect data from this app** if the questionnaire allows — OpenChat does not transmit data to OpenChat-operated servers.

**Third-party data:** Users voluntarily send messages, attachments, and search queries to AI/search APIs they configure. That processing is between the user and those providers, not OpenChat infrastructure. Document this in the privacy policy (done) and App Review notes (below).

## App Review notes (paste into “Notes” field)

```
OpenChat is a bring-your-own-key (BYOK) native iOS chat client. There is no OpenChat login or backend.

TEST ACCOUNT / API KEYS
- Reviewers must add their own API key from any supported provider (OpenAI, Anthropic, OpenRouter, etc.) on first launch via “Connect a Provider”, or use a pre-release key we provide separately if requested.
- Web search is optional and requires a separate search-provider key in Settings → Web Search.

NETWORK / ATS
- NSAllowsArbitraryLoads is enabled so users can connect custom OpenAI-compatible base URLs (self-hosted Ollama, LM Studio, corporate gateways). Production traffic goes only to endpoints the user configures.

GENERATIVE AI
- The app sends user prompts and attachments directly to third-party LLM APIs selected by the user. OpenChat does not moderate or filter model output server-side.

SKILLS (BETA)
- Settings → Tools → Skills is labeled Beta. Skills are user-defined prompt shortcuts invoked with “/” in the composer.

BACKGROUND GENERATION
- When the user leaves a chat during generation, a Live Activity and optional local notification may appear on-device when the reply completes. No OpenChat server is involved.

VOICE MODE
- Hidden/disabled in this build if VoiceModeStore.isFeatureVisible is false for App Store 1.0.

PRIVACY POLICY
- https://robert-garay.github.io/openchat/privacy-policy.html (GitHub Pages from docs/privacy-policy.html)
```

## Screenshot shot list (6.7" iPhone — 1290 × 2796)

Capture on device or simulator with representative API keys and **no real secrets** in screenshots.

| # | Screen | Caption idea | Setup |
|---|---|---|---|
| 1 | Welcome / Connect a Provider | “One app. Every model.” | First launch or empty providers |
| 2 | Active chat (streaming assistant reply) | “Native chat with Markdown & code” | Long assistant message with code block |
| 3 | Model picker | “Switch providers without switching apps” | Open model sheet with multiple providers |
| 4 | Settings → Providers | “Your keys, your providers (BYOK)” | 2–3 providers connected, balances optional |
| 5 | Web Search settings | “Optional web search, your search keys” | One search provider configured |
| 6 | Rules or Memory | “Steer behavior with rules & memory” | Sample global rule + memory list |
| 7 | Skills (beta) | “Reusable prompts with / commands” | Skills list + composer slash menu |
| 8 | Background / Live Activity (optional) | “Replies finish in the background” | Live Activity or lock-screen notification mock |

Also export **6.5"** and **iPad Pro 12.9"** sizes if targeting universal iPhone + iPad (`TARGETED_DEVICE_FAMILY: 1,2`).

## Privacy policy hosting

- Source: `docs/privacy-policy.html` in the repo.
- **GitHub Pages:** workflow `.github/workflows/pages.yml` publishes to `https://robert-garay.github.io/openchat/privacy-policy.html`.
- **One-time setup in GitHub:** Settings → Pages → Source = **GitHub Actions**.
- Fallback URL (works without Pages): `https://github.com/robert-garay/openchat/blob/main/docs/privacy-policy.html` (less ideal for App Store; prefer Pages).

## Pre-submit checklist (manual)

- [ ] Enable GitHub Pages (Actions) on the repo
- [ ] Confirm privacy policy URL loads over HTTPS
- [ ] Create `Config/Local.xcconfig` from example with valid `DEVELOPMENT_TEAM`
- [ ] Archive Release build in Xcode; upload to App Store Connect / TestFlight
- [ ] Capture screenshots on physical device where possible
- [ ] Complete App Privacy questionnaire and age rating
- [ ] Paste App Review notes and verify API key instructions for reviewers

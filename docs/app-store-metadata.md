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
| **Marketing URL** | https://robert-garay.github.io/openchat/ |
| **Pricing** | Free (users pay AI providers directly via their own API keys) |

## Promotional text (170 chars, editable without new build)

Chat with OpenAI, Claude, Gemini, OpenRouter, and your own endpoints from one native iOS app. BYOK, on-device history, web search, rules, memory, and skills.

## Description

OpenChat is the native iOS home for every major LLM.

Connect your own API keys and chat with OpenAI, Anthropic, Google Gemini, OpenRouter, Mistral, DeepSeek, Qwen, Kimi, Z.ai, 01.AI, or any OpenAI-compatible endpoint (Ollama, LM Studio, vLLM, internal gateways) from one clean interface.

**Why OpenChat**
- One workflow across providers: switch models without changing apps
- Live model catalogs from supported providers
- Bring your own key (BYOK): no OpenChat account, no backend
- Chats, rules, memory, and skills stay on your device

**Features**
- Multi-provider chat with streaming Markdown, tables, and syntax-highlighted code
- Web search via Tavily, Exa, Brave, Serper, or SerpAPI (your keys)
- Global and per-chat rules; editable memory; slash-command skills (beta)
- Image attachments for vision models; background replies with Live Activity and local notification when complete
- Compact context mode and light/dark appearance

OpenChat does not include ads or analytics SDKs. When you send a message, data goes directly from your device to the AI or search provider you configured, under that provider's terms.

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

## Export compliance

| Question | Answer |
|---|---|
| Uses encryption? | **Yes**: HTTPS for all API traffic |
| Exempt from export compliance documentation? | **Yes**: app uses only standard HTTPS/TLS (no proprietary encryption) |
| Select in App Store Connect | "Your app uses encryption" → "Yes" → exempt (standard encryption only) |

## Content rights

| Question | Answer |
|---|---|
| Third-party content in app? | **No**: app does not bundle third-party content; all chat content is user-generated via third-party APIs |
| Rights to all content? | **Yes**: app UI, icons, and code are original or MIT-licensed open source |
| Made for Kids | **No** |

## Pricing and availability

| Field | Value |
|---|---|
| **Price** | Free |
| **In-app purchases** | None |
| **Subscriptions** | None |
| **Availability** | All territories (or restrict as desired) |
| **Pre-order** | No |

## App Privacy (Privacy Nutrition Labels)

**Data linked to you:** None collected by the developer (OpenChat has no backend).

**Data not linked to you:** None collected by the developer.

**Data used to track you:** None.

**Developer data collection:** Select **No, we do not collect data from this app** if the questionnaire allows, OpenChat does not transmit data to OpenChat-operated servers.

**Third-party data:** Users voluntarily send messages, attachments, and search queries to AI/search APIs they configure. That processing is between the user and those providers, not OpenChat infrastructure. Document this in the privacy policy (done) and App Review notes (below).

## App Review notes (paste into "Notes" field)

Full paste-ready copy: [`docs/launch/app-review-notes.txt`](../launch/app-review-notes.txt)

```
OpenChat is a bring-your-own-key (BYOK) native iOS chat client. There is no OpenChat login, no OpenChat account, and no OpenChat backend server.

TEST ACCOUNT / API KEYS
- Reviewers must add their own API key from any supported provider on first launch via "Connect a Provider".
- Supported providers: OpenAI, Anthropic, Google Gemini, OpenRouter, Mistral, DeepSeek, Alibaba Cloud, Moonshot AI, Z.ai, 01.AI, and custom OpenAI-compatible endpoints.
- Alternatively, contact robert@genion.ai to request a pre-release API key for review purposes.
- Web search is optional and requires a separate search-provider key in Settings > Tools > Web Search.

HOW TO TEST
1. Launch → "Connect a Provider" → paste an API key.
2. Start a chat and send a message.
3. Optional: Settings > Tools > Rules, Memory, Web Search.

NETWORK / ATS
- NSAllowsArbitraryLoads is enabled for custom OpenAI-compatible base URLs (Ollama, LM Studio, corporate gateways). Traffic goes only to endpoints the user configures.

GENERATIVE AI
- User prompts and attachments go directly to third-party LLM APIs selected by the user. No server-side moderation.

SKILLS (BETA): Settings > Tools > Skills; invoked with "/" in composer.
BACKGROUND GENERATION: Live Activity + local notification on completion; no OpenChat server.
VOICE MODE: Hidden in App Store 1.0 build.

PRIVACY POLICY: https://robert-garay.github.io/openchat/privacy-policy.html
SUPPORT: https://github.com/robert-garay/openchat/issues
CONTACT: robert@genion.ai
```

## Reviewer API key guidance (for Robert to fill)

> **Action required before submit:** Decide whether to provide Apple reviewers a test API key or instruct them to use their own.

**Option A: Reviewer uses own key (default in notes above):**
No setup needed. Apple reviewers add any supported provider key on first launch.

**Option B: Provide a pre-release key:**
1. Create a dedicated API key with a spending cap (e.g., OpenRouter or OpenAI key limited to $5).
2. Paste the key into App Review notes: `Test API key: sk-...`
3. Note which provider it is configured for and any usage limits.
4. Revoke the key after approval.

**Recommended:** Option B if you want to reduce reviewer friction. Fill in below before submitting:

```
Test provider: [OpenRouter / OpenAI / other]
Test API key: [PASTE KEY HERE]
Spending cap: [$X]
Key expires: [date]
```

## Screenshot shot list

See [`docs/launch/screenshot-guide.md`](../launch/screenshot-guide.md) for exact device sizes, shot-by-shot prompts, overlay text, dark/light mode recommendations, and export settings.

## Landing page and privacy policy hosting

| Resource | URL (after Pages deploy) | Source |
|---|---|---|
| Landing page | https://robert-garay.github.io/openchat/ | `website/index.html` |
| Privacy policy | https://robert-garay.github.io/openchat/privacy-policy.html | `docs/privacy-policy.html` |
| GitHub repo | https://github.com/robert-garay/openchat | N/A |
| Support | https://github.com/robert-garay/openchat/issues | N/A |

- **GitHub Pages:** workflow `.github/workflows/pages.yml` deploys on push to `main`.
- **One-time setup in GitHub:** Settings → Pages → Source = **GitHub Actions**.

## Launch copy package

Ready-to-paste launch materials in `docs/launch/`:

| File | Purpose |
|---|---|
| `product-hunt.md` | Product Hunt listing + maker comment |
| `hacker-news.md` | Show HN title + post body |
| `press-email-template.md` | Personalized outreach email |
| `launch-day-social.md` | X thread, LinkedIn, Reddit posts |
| `testflight-invite.md` | Beta tester recruitment |
| `app-review-notes.txt` | Paste-ready App Review notes |
| `apple-editorial-nomination.md` | Apple editorial feature nomination |
| `screenshot-guide.md` | Screenshot production guide |

## Pre-submit checklist (manual)

- [ ] Enable GitHub Pages (Actions) on the repo
- [ ] Confirm landing page and privacy policy URLs load over HTTPS
- [ ] Fill in reviewer API key section above (Option A or B)
- [ ] Create `Config/Local.xcconfig` from example with valid `DEVELOPMENT_TEAM`
- [ ] Archive Release build in Xcode; upload to App Store Connect / TestFlight
- [ ] Capture screenshots per `docs/launch/screenshot-guide.md`
- [ ] Complete App Privacy questionnaire and age rating
- [ ] Paste App Review notes from `docs/launch/app-review-notes.txt`

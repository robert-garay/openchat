# Launch Campaign Execution Pack

**Campaign:** `launch2026` (2026-09-26 → 2026-11-26)  
**App Store:** https://apps.apple.com/us/app/openchat-connect/id6798106079  
**Landing (UTM base):** `https://robert-garay.github.io/openchat/?utm_campaign=launch2026`

**Site dependency:** Live App Store CTAs on GitHub Pages shipped in [PR #293](https://github.com/robert-garay/openchat/pull/293) (merged). No blocker for outbound posts.

**Robert publishes** HN, X, LinkedIn, Reddit, and Product Hunt. **Agent** maintains copy, UTMs, changelog, and KPI docs. Weekly ASC numbers: see [`asc-kpi-export-guide.md`](asc-kpi-export-guide.md).

---

## UTM-tagged marketing links

Use the **landing page** link below in posts (not the App Store URL). App Store link stays canonical for installs; landing page carries attribution.

| Channel | `utm_source` | `utm_medium` | Full URL |
|---------|--------------|--------------|----------|
| Hacker News (Show HN) | `hackernews` | `show` | https://robert-garay.github.io/openchat/?utm_source=hackernews&utm_medium=show&utm_campaign=launch2026 |
| X (thread) | `twitter` | `thread` | https://robert-garay.github.io/openchat/?utm_source=twitter&utm_medium=thread&utm_campaign=launch2026 |
| LinkedIn | `linkedin` | `post` | https://robert-garay.github.io/openchat/?utm_source=linkedin&utm_medium=post&utm_campaign=launch2026 |
| Reddit (r/iOSProgramming) | `reddit` | `post` | https://robert-garay.github.io/openchat/?utm_source=reddit&utm_medium=post&utm_campaign=launch2026&utm_content=iosprogramming |
| Product Hunt | `producthunt` | `launch` | https://robert-garay.github.io/openchat/?utm_source=producthunt&utm_medium=launch&utm_campaign=launch2026 |

**App Store (all channels):** https://apps.apple.com/us/app/openchat-connect/id6798106079

---

## Hacker News — Show HN (copy-paste)

**Title**

```
Show HN: OpenChat – native iOS app for every major LLM (BYOK, no backend, open source)
```

**Body**

```
I built OpenChat because I kept switching between separate apps every time a different model was best for the task. I wanted one native iOS client where I could use OpenRouter, DeepSeek, Qwen, Mistral, OpenAI, Claude, Gemini, and my self-hosted Ollama endpoint without fragmenting my workflow.

**What it is:** A native SwiftUI iOS app (Swift 6, SwiftData) that lets you connect your own API keys and chat with multiple LLM providers from one interface.

**What it is not:** There's no OpenChat backend, no account system, and no telemetry. API keys go in the iOS Keychain. Chats, rules, memory, and skills stay on your device. When you send a message, it goes directly from your phone to whichever provider you configured.

**Features:**
- Multi-provider chat with streaming Markdown, tables, and syntax-highlighted code
- Live model catalogs from supported providers + OpenRouter
- Web search via Tavily, Exa, Brave, Serper, or SerpAPI (optional, your keys)
- Global and per-chat rules, editable on-device memory
- Slash-command skills (beta)
- Background generation with Live Activity and local notification
- Image attachments for vision models
- Custom OpenAI-compatible endpoints (Ollama, LM Studio, vLLM, etc.)

**Tech:** Swift 6, SwiftUI, SwiftData, Keychain, no third-party analytics SDKs. One dependency for Markdown rendering (SwiftStreamingMarkdown).

**Open source:** MIT: https://github.com/robert-garay/openchat

**App Store:** https://apps.apple.com/us/app/openchat-connect/id6798106079 · Landing page: https://robert-garay.github.io/openchat/?utm_source=hackernews&utm_medium=show&utm_campaign=launch2026

**Requirements:** BYOK: you need your own API key from a supported provider. The app is free; you pay providers directly.

Happy to answer questions about the architecture, privacy model, or why I chose native iOS over a web wrapper.
```

Source: [`hacker-news.md`](hacker-news.md)

---

## X (Twitter) — 5-tweet thread (copy-paste)

**Tweet 1**

```
OpenChat is live on the App Store.

Every model. One app. Your device.

Native iOS home for OpenRouter, DeepSeek, Qwen, Mistral, OpenAI, Claude, Gemini, and every OpenAI-compatible endpoint.

BYOK. No backend. No analytics. Open source.

https://apps.apple.com/us/app/openchat-connect/id6798106079
https://robert-garay.github.io/openchat/?utm_source=twitter&utm_medium=thread&utm_campaign=launch2026
```

**Tweet 2**

```
The best model changes by task and by week. Switching between five AI apps means fragmented history and different UIs.

OpenChat gives you one native workflow across every provider you already use.
```

**Tweet 3**

```
Your API keys → iOS Keychain.
Your chats → on your device (SwiftData).
Your messages → directly to the provider you chose.

No OpenChat servers. No telemetry SDKs. No ads.
```

**Tweet 4**

```
- Streaming Markdown + code blocks
- Live model catalogs
- Web search (Tavily, Exa, Brave, Serper, SerpAPI)
- Rules & on-device memory
- Background generation + Live Activity
- Custom endpoints (Ollama, LM Studio, vLLM)
```

**Tweet 5**

```
MIT licensed. Inspect the code, build it yourself, or contribute.

GitHub: https://github.com/robert-garay/openchat

Questions? Reply here or open an issue.
```

Source: [`launch-day-social.md`](launch-day-social.md)

---

## LinkedIn — single post (copy-paste)

```
I'm excited to share OpenChat: a native iOS app I built for anyone who uses multiple AI providers.

The idea is simple: the best LLM changes by task, by week, and by provider. But juggling separate apps for OpenAI, Claude, Gemini, and OpenRouter fragments your workflow and your history.

OpenChat is a bring-your-own-key (BYOK) client. You connect API keys from providers you already have, pick the right model per conversation, and keep everything in one native iOS interface.

What matters to me:
- **Privacy by design**: no OpenChat backend, no analytics SDKs, chats stay on your device
- **No lock-in**: switch models and providers without changing apps
- **Open source**: MIT licensed at github.com/robert-garay/openchat

Features include streaming Markdown, live model catalogs, optional web search, rules & memory, and support for self-hosted endpoints.

https://apps.apple.com/us/app/openchat-connect/id6798106079
Landing page: https://robert-garay.github.io/openchat/?utm_source=linkedin&utm_medium=post&utm_campaign=launch2026

If you try it, I'd love your feedback.
```

Source: [`launch-day-social.md`](launch-day-social.md)

---

## Reddit — r/iOSProgramming (copy-paste)

**Title**

```
I built OpenChat: a native SwiftUI app for chatting with every major LLM (BYOK, SwiftData, no backend)
```

**Body**

```
Hey r/iOSProgramming,

I built OpenChat, a native iOS chat app for multiple LLM providers. Thought this community might appreciate the technical approach.

**Stack:** Swift 6, SwiftUI, SwiftData, Keychain Services. iOS 17+. XcodeGen for project generation. One SPM dependency (SwiftStreamingMarkdown for streaming Markdown rendering).

**Architecture highlights:**
- BYOK: API keys in Keychain, requests go directly to configured provider endpoints
- No backend: all chat history, rules, memory, skills stored locally via SwiftData
- Multi-provider abstraction with live `/models` catalog fetching
- Background URLSession for generation that survives app backgrounding
- Live Activity + local notifications for background reply completion
- NSAllowsArbitraryLoads for custom OpenAI-compatible base URLs (Ollama, etc.)

**Open source:** https://github.com/robert-garay/openchat (MIT)

**App Store:** https://apps.apple.com/us/app/openchat-connect/id6798106079

**Landing:** https://robert-garay.github.io/openchat/?utm_source=reddit&utm_medium=post&utm_campaign=launch2026&utm_content=iosprogramming

Happy to discuss implementation details: concurrency model, SwiftData schema, provider client architecture, etc.
```

Optional second post (r/LocalLLaMA): full copy in [`launch-day-social.md`](launch-day-social.md).

---

## Product Hunt — launch day checklist (Pacific Time)

Schedule PH for a **Tuesday–Thursday** morning if possible. Prep copy in [`product-hunt.md`](product-hunt.md). Maker link: UTM landing URL above.

| Time (PT) | Action | Owner |
|-----------|--------|-------|
| **T-7 days** | Confirm PH listing draft (tagline, gallery, topics). Line up 5–10 friends to upvote/comment in first hour (no paid votes). | Robert |
| **T-1 day** | Queue X thread + LinkedIn; draft HN/Reddit for day after PH spike (or same day if energy allows). | Robert |
| **00:01** | Publish Product Hunt listing (goes live at midnight PT). Post maker comment from `product-hunt.md` within 5 minutes. | Robert |
| **00:05** | Pin maker comment; reply to every early question. | Robert |
| **00:15** | Share PH link on X (single tweet, not full thread yet) + LinkedIn with UTM landing + App Store. | Robert |
| **00:30–02:00** | Engage: thank commenters, answer technical questions, link GitHub/wiki for depth. | Robert |
| **06:00** | Morning push: second X post or quote-tweet PH; ask open-source followers to try + honest review. | Robert |
| **08:00–10:00** | Peak engagement window: stay in PH tab; do not spam other channels. | Robert |
| **12:00** | Midday check: leaderboard position; post one update on X if milestone (e.g. top 10). | Robert |
| **15:00** | Consider Show HN **next morning** if PH day is crowded (HN + PH same day splits attention). | Robert |
| **18:00** | Thank-you post on X; capture screenshot of PH rank for campaign log. | Robert |
| **End of day** | Log touchpoint in campaign log; note spike date for ASC correlation. | Agent + Robert |
| **+24 h** | Export ASC daily units for launch day + prior day (see KPI guide). | Robert |

---

## Personal review request (ethical template)

Use only with people who **actually used** OpenChat with their own API key. No incentives, no quid pro quo, no star-rating instructions.

**Subject (email/DM):** Quick favor — OpenChat on the App Store?

**Body**

```
Hi [Name],

You mentioned you tried OpenChat / we set up [provider] together — thank you again for the feedback on [specific thing they said].

If you have a minute and the app is still useful to you, an honest rating or short review on the App Store helps other BYOK users discover it. No pressure at all — only if you genuinely want to share your experience.

App Store: https://apps.apple.com/us/app/openchat-connect/id6798106079

If something’s broken or confusing, tell me directly first — I’d rather fix it than chase stars.

Thanks,
Robert
```

**Do not:** offer gift cards, refunds, TestFlight perks for reviews, or ask for a specific star count. **Do:** respond to every App Store review within 48 hours (agent can draft replies).

---

## Related docs

| Doc | Purpose |
|-----|---------|
| [`asc-kpi-export-guide.md`](asc-kpi-export-guide.md) | Weekly ASC metrics for agent KPI table |
| [`product-hunt.md`](product-hunt.md) | PH tagline, description, maker comment |
| [`hacker-news.md`](hacker-news.md) | Canonical Show HN source |
| [`launch-day-social.md`](launch-day-social.md) | Canonical social + Reddit sources |
| [`launch-execution-checklist.md`](launch-execution-checklist.md) | App Store submission (pre-launch) |

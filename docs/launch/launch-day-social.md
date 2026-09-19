# Launch Day Social Copy

## X (Twitter) thread

**Tweet 1 (announcement)**
OpenChat is live on the App Store.

Every model. One app. Your device.

Native iOS home for GPT-6 Astra, Claude Fable 5.1, Gemini, OpenRouter, and every OpenAI-compatible endpoint.

BYOK. No backend. No analytics. Open source.

[App Store link]
https://robert-garay.github.io/openchat/

**Tweet 2 (problem/solution)**
The best model changes by task and by week. Switching between the Astra app and the Claude app means fragmented history and different UIs.

OpenChat lets you switch between Astra and Fable without switching apps.

**Tweet 3 (privacy)**
Your API keys → iOS Keychain.
Your chats → on your device (SwiftData).
Your messages → directly to the provider you chose.

No OpenChat servers. No telemetry SDKs. No ads.

**Tweet 4 (features)**
- Streaming Markdown + code blocks
- Live model catalogs
- Web search (Tavily, Exa, Brave, Serper, SerpAPI)
- Rules & on-device memory
- Background generation + Live Activity
- Custom endpoints (Ollama, LM Studio, vLLM)

**Tweet 5 (open source + CTA)**
MIT licensed. Inspect the code, build it yourself, or contribute.

GitHub: https://github.com/robert-garay/openchat

Questions? Reply here or open an issue.

---

## LinkedIn post

I built OpenChat, a native iOS app for anyone who uses more than one AI provider.

The idea is simple: the best LLM changes by task, by week, and by provider. But juggling separate apps for Astra and Fable fragments your workflow and your history.

OpenChat is a bring-your-own-key (BYOK) client. You connect API keys from providers you already have, pick the right model per conversation, and keep everything in one native iOS interface.

What matters to me:
- **Privacy by design**: no OpenChat backend, no analytics SDKs, chats stay on your device
- **No lock-in**: switch between Astra and Fable without changing apps
- **Open source**: MIT licensed at github.com/robert-garay/openchat

Features include streaming Markdown, live model catalogs, optional web search, rules & memory, and support for self-hosted endpoints.

[App Store link when live]
Landing page: https://robert-garay.github.io/openchat/

If you try it, I'd love your feedback.

---

## Reddit: r/iOSProgramming

**Title:** I built OpenChat: a native SwiftUI app for chatting with every major LLM (BYOK, SwiftData, no backend)

**Body:**

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

**App Store:** [link when live]

Happy to discuss implementation details: concurrency model, SwiftData schema, provider client architecture, etc.

---

## Reddit: r/LocalLLaMA

**Title:** OpenChat: native iOS client for Ollama, OpenRouter, and every OpenAI-compatible endpoint (BYOK, open source)

**Body:**

Built a native iOS app for multi-provider LLM chat, including full support for custom OpenAI-compatible endpoints.

**Why it exists:** I run local models via Ollama and cloud models via OpenRouter/OpenAI/Claude. I wanted one app with one chat history and one UI: not five separate clients.

**Local/self-hosted support:**
- Add any OpenAI-compatible endpoint from Settings (Ollama, LM Studio, vLLM, internal gateways)
- NSAllowsArbitraryLoads enabled so you can point at local network IPs
- Live model catalog fetch from your endpoint's `/models`

**Other providers:** OpenAI, Anthropic, Google Gemini, OpenRouter, Mistral, DeepSeek, Qwen, Kimi, Z.ai, 01.AI

**Privacy:** BYOK, no OpenChat backend, chats stay on device. No analytics SDKs.

**Open source:** https://github.com/robert-garay/openchat

**App Store:** [link when live] | Landing: https://robert-garay.github.io/openchat/

Would love feedback from folks running local models: especially around endpoint configuration and model discovery.

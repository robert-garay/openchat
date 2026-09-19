# Launch Day Social Copy

## X (Twitter) thread

**Tweet 1 (announcement)**
OpenChat is live on the App Store.

Pay for performance, not a logo.

One native iOS app for OpenRouter, DeepSeek, Qwen, Mistral, and Llama.

BYOK. No backend. No analytics. Open source.

[App Store link]
https://robert-garay.github.io/openchat/

**Tweet 2 (problem/solution)**
Flagship APIs charge flagship prices. DeepSeek, Qwen, and Llama via OpenRouter often match them for a fraction of the cost.

OpenChat lets you route by price and performance without switching apps.

**Tweet 3 (privacy)**
Your API keys → iOS Keychain.
Your chats → on your device (SwiftData).
Your messages → directly to the provider you chose.

No OpenChat servers. No telemetry SDKs. No ads.

**Tweet 4 (features)**
- OpenRouter catalog + direct providers
- Streaming Markdown + code blocks
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

I built OpenChat, a native iOS app for anyone who routes between models by price and quality.

Most of my prompts don't need a flagship logo. OpenRouter gives me DeepSeek, Qwen, Mistral, and Llama on one key. I wanted one native workflow instead of five apps and fragmented history.

OpenChat is bring-your-own-key (BYOK). Connect OpenRouter or direct providers, pick the cheapest model that's good enough, and keep everything in one interface.

What matters to me:
- **Pay for performance, not a logo**: route open-source-friendly models through OpenRouter
- **Privacy by design**: no OpenChat backend, no analytics SDKs, chats stay on your device
- **Open source**: MIT licensed at github.com/robert-garay/openchat

Features include streaming Markdown, live model catalogs, optional web search, rules & memory, and self-hosted endpoints.

[App Store link when live]
Landing page: https://robert-garay.github.io/openchat/

If you try it, I'd love your feedback.

---

## Reddit: r/iOSProgramming

**Title:** I built OpenChat: a native SwiftUI app for OpenRouter + multi-provider LLM chat (BYOK, SwiftData, no backend)

**Body:**

Hey r/iOSProgramming,

I built OpenChat, a native iOS chat app for multi-provider LLM routing. Thought this community might appreciate the technical approach.

**Stack:** Swift 6, SwiftUI, SwiftData, Keychain Services. iOS 17+. XcodeGen for project generation. One SPM dependency (SwiftStreamingMarkdown for streaming Markdown rendering).

**Architecture highlights:**
- BYOK: API keys in Keychain, requests go directly to configured provider endpoints
- OpenRouter-first catalog normalization with direct provider support
- No backend: all chat history, rules, memory, skills stored locally via SwiftData
- Background URLSession for generation that survives app backgrounding
- Live Activity + local notifications for background reply completion
- NSAllowsArbitraryLoads for custom OpenAI-compatible base URLs (Ollama, etc.)

**Open source:** https://github.com/robert-garay/openchat (MIT)

**App Store:** [link when live]

Happy to discuss implementation details: concurrency model, SwiftData schema, provider client architecture, etc.

---

## Reddit: r/LocalLLaMA

**Title:** OpenChat: native iOS client for Ollama, OpenRouter, DeepSeek, Qwen, and every OpenAI-compatible endpoint (BYOK, open source)

**Body:**

Built a native iOS app for multi-provider LLM chat, including full support for custom OpenAI-compatible endpoints.

**Why it exists:** I run local models via Ollama and cheap cloud models via OpenRouter (DeepSeek, Qwen, Mistral, Llama). I wanted one app with one chat history and one UI: not five separate clients.

**Local/self-hosted support:**
- Add any OpenAI-compatible endpoint from Settings (Ollama, LM Studio, vLLM, internal gateways)
- NSAllowsArbitraryLoads enabled so you can point at local network IPs
- Live model catalog fetch from your endpoint's `/models`

**OpenRouter / open models:** One key, hundreds of models. Route by price without leaving the app.

**Other providers:** Direct keys for OpenAI, Anthropic, Gemini, Mistral, DeepSeek, Qwen, Kimi, Z.ai, and 01.AI also work.

**Privacy:** BYOK, no OpenChat backend, chats stay on device. No analytics SDKs.

**Open source:** https://github.com/robert-garay/openchat

**App Store:** [link when live] | Landing: https://robert-garay.github.io/openchat/

Would love feedback from folks running local models, especially around endpoint configuration and model discovery.

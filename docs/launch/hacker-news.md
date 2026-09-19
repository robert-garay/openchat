# Hacker News: Show HN

## Title

Show HN: OpenChat – native iOS BYOK client with OpenRouter routing (no backend, open source)

## Post body

I built OpenChat because I wanted one native iOS workflow for cost-aware model routing. OpenRouter gives you DeepSeek, Qwen, Mistral, Llama, and hundreds of other models on one key. I was tired of switching apps every time I changed price tier or provider.

**What it is:** A native SwiftUI iOS app (Swift 6, SwiftData) that lets you connect your own API keys and chat with OpenRouter, DeepSeek, Qwen, Mistral, direct providers, and self-hosted OpenAI-compatible endpoints from one interface.

**The angle:** Pay for performance, not a logo. Use cheap, capable open-weight and open-source-friendly models for most tasks. Keep flagship APIs available when you actually need them.

**What it is not:** There's no OpenChat backend, no account system, and no telemetry. API keys go in the iOS Keychain. Chats, rules, memory, and skills stay on your device. When you send a message, it goes directly from your phone to whichever provider you configured.

**Features:**
- Multi-provider chat with streaming Markdown, tables, and syntax-highlighted code
- Live model catalogs from OpenRouter and supported direct providers
- Web search via Tavily, Exa, Brave, Serper, or SerpAPI (optional, your keys)
- Global and per-chat rules, editable on-device memory
- Slash-command skills (beta)
- Background generation with Live Activity and local notification
- Image attachments for vision models
- Custom OpenAI-compatible endpoints (Ollama, LM Studio, vLLM, etc.)

**Tech:** Swift 6, SwiftUI, SwiftData, Keychain, no third-party analytics SDKs. One dependency for Markdown rendering (SwiftStreamingMarkdown).

**Open source:** MIT: https://github.com/robert-garay/openchat

**App Store:** Coming soon. Landing page: https://robert-garay.github.io/openchat/

**Requirements:** BYOK: you need your own API key from a supported provider. OpenRouter is the fastest way in. The app is free; you pay providers directly.

Happy to answer questions about the architecture, privacy model, or how we normalize OpenRouter vs. direct provider catalogs.

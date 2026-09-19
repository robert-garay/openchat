# Hacker News: Show HN

## Title

Show HN: OpenChat – native iOS app for every major LLM (BYOK, no backend, open source)

## Post body

I built OpenChat because I kept switching between separate apps every time a different model was best for the task. I wanted one native iOS client where I could use OpenAI, Claude, Gemini, OpenRouter, and my self-hosted Ollama endpoint without fragmenting my workflow.

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

**App Store:** Coming soon. Landing page: https://robert-garay.github.io/openchat/

**Requirements:** BYOK: you need your own API key from a supported provider. The app is free; you pay providers directly.

Happy to answer questions about the architecture, privacy model, or why I chose native iOS over a web wrapper.

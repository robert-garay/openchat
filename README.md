# OpenChat

A native iOS chat app for talking to any LLM — OpenAI, Claude, Gemini, OpenRouter, and leading Chinese open models (DeepSeek, Qwen, Kimi/Moonshot, Zhipu GLM, 01.AI) — plus any custom OpenAI-compatible endpoint (Ollama, LM Studio, vLLM). Built with SwiftUI + SwiftData, no third-party dependencies, no backend server: the app talks directly to whichever provider you configure, and your API keys stay in the iOS Keychain on your device.

## Requirements

- macOS with Xcode 16+
- An Apple Developer account (free is enough to run on your own device; a paid account is required for TestFlight)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```bash
xcodegen generate      # regenerates OpenChat.xcodeproj from project.yml
open OpenChat.xcodeproj
```

The `.xcodeproj` is committed to the repo, so you can also just open it directly — only re-run `xcodegen generate` after pulling changes to `project.yml` or adding/removing files.

Signing defaults to bundle id `com.genion.openchat`. Set your Apple Team ID once by copying `Config/Local.xcconfig.example` → `Config/Local.xcconfig` (gitignored) and filling in `DEVELOPMENT_TEAM`.

## Adding a model

On first launch, tap **Connect a Provider**, pick a provider, and paste in an API key. Get keys here:

| Provider | Console |
|---|---|
| DeepSeek | platform.deepseek.com |
| Alibaba Cloud | bailian.console.aliyun.com |
| Moonshot AI | platform.moonshot.cn |
| Zhipu AI | open.bigmodel.cn |
| OpenAI | platform.openai.com |
| Anthropic | console.anthropic.com |
| OpenRouter | openrouter.ai |

You can also add any OpenAI-compatible endpoint (self-hosted Ollama, LM Studio, vLLM, an internal gateway) from Settings → Add a Provider → Custom Endpoint.

## Web search (optional)

Settings → Web Search → add keys for one or more search providers:

| Provider | Console |
|---|---|
| Tavily | app.tavily.com |
| Exa | dashboard.exa.ai |
| Brave Search | api-dashboard.search.brave.com |
| Serper | serper.dev |
| SerpAPI | serpapi.com |

In chat, tap the **web search** button to pick a registered provider (logo when active) or turn search off (globe). No crawl/extract.

- **Tool-capable models** use native function/tool calling (`web_search`)
- **All other models** fall back to injecting search results into the prompt

Search keys are stored in the iOS Keychain, same as provider keys.

## Ship to TestFlight

1. In Xcode: **Product → Archive** (requires a physical device or "Any iOS Device" build target, not the simulator).
2. In the Organizer window that opens, select the archive → **Distribute App → App Store Connect → Upload**.
3. In [App Store Connect](https://appstoreconnect.apple.com), create the app record (if it doesn't exist yet) matching your bundle ID, then open **TestFlight** for that app once the build finishes processing.
4. Add yourself (and other testers) under **Internal Testing**, attach the build, and install via the TestFlight app.

Bump `CURRENT_PROJECT_VERSION` in `project.yml` (or directly in the target's build settings) before each new TestFlight upload — App Store Connect rejects duplicate build numbers.

## Project layout

```
OpenChat/
  App/            App entry point
  Models/         Provider/model catalog, SwiftData models (Conversation, ChatMessage)
  Services/       Networking (OpenAI-compatible + Anthropic streaming clients), Keychain, ProviderStore
  Features/       Onboarding, Chat, Chat List, Settings — one folder per screen
  DesignSystem/   Shared colors, spacing, animation, haptics
OpenChatTests/    Unit tests for the provider catalog, Keychain, SSE parsing, and provider storage
```

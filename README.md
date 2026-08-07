# OpenChat

A native iOS chat app for talking to any LLM — OpenAI, Claude, Gemini, OpenRouter, and leading Chinese open models (DeepSeek, Qwen, Kimi/Moonshot, Z.ai GLM, 01.AI) — plus any custom OpenAI-compatible endpoint (Ollama, LM Studio, vLLM).

No backend server, no account, no telemetry: the app talks directly to whichever provider you configure, and everything — API keys, chat history, memory, rules, skills — stays on your device.

## Features

- **Any provider, one app** — switch between OpenAI, Anthropic, Gemini, OpenRouter, Chinese model providers, or a self-hosted/custom OpenAI-compatible endpoint, all from the same chat UI.
- **Private by design** — API keys live in the iOS Keychain, chats are stored locally via SwiftData, and nothing is sent anywhere except the LLM provider you chose for that message.
- **Web search** — attach a search provider (Tavily, Exa, Brave, Serper, SerpAPI) and let tool-capable models call it natively, or fall back to prompt injection for models without tool support.
- **Rules** — steer model behavior with global rules that apply everywhere, or per-chat rules scoped to a single conversation.
- **Memory** — the app can remember facts across chats; review, edit, pin, or delete anything it's stored at any time.
- **Skills** — define reusable prompts and invoke them instantly with a `/` slash command while composing a message.
- **Rich chat rendering** — Markdown, tables, syntax-highlighted code blocks, selectable message text, and image attachments (camera or photo library, for vision-capable models).

## Connecting a provider

On first launch, tap **Connect a Provider**, pick a provider, and paste in an API key. Get keys here:

| Provider | Console |
|---|---|
| OpenAI | platform.openai.com |
| Anthropic | console.anthropic.com |
| OpenRouter | openrouter.ai |
| DeepSeek | platform.deepseek.com |
| Alibaba Cloud (Qwen) | bailian.console.aliyun.com |
| Moonshot AI (Kimi) | platform.moonshot.cn |
| Z.ai (GLM) | z.ai/model-api |

You can also add any OpenAI-compatible endpoint (self-hosted Ollama, LM Studio, vLLM, an internal gateway) from Settings → Add a Provider → Custom Endpoint.

## Web search

Settings → Web Search → add a key for one or more search providers (Tavily, Exa, Brave Search, Serper, SerpAPI). In chat, tap the web search button to pick a registered provider or turn search off. Search keys are stored in the iOS Keychain, same as provider keys.

## Privacy

OpenChat has no backend, no analytics, and no third-party dependencies — it's built with SwiftUI + SwiftData only. API keys and search keys are stored in the iOS Keychain; chats, rules, memory, and skills are stored locally on-device. See the [privacy policy](docs/privacy-policy.html) for the full details on optional calendar/health data access.

## Building from source

Requires macOS with Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate      # regenerates OpenChat.xcodeproj from project.yml
open OpenChat.xcodeproj
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for full setup, testing, and release instructions.

## License

MIT — see [LICENSE](LICENSE).

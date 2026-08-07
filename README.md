# OpenChat

The native iOS home for every major LLM.

OpenChat puts OpenAI, Anthropic, Google Gemini, OpenRouter, Mistral AI, DeepSeek, Alibaba Cloud (Qwen), Moonshot AI (Kimi), Z.ai, 01.AI, and any OpenAI-compatible endpoint (Ollama, LM Studio, vLLM, internal gateways) into one clean app.

Provider-specific chat apps are good at one thing: their own model. OpenChat is built for the reality that the best model changes by task, by week, and by provider. You get one workflow, one interface, and no lock-in.

OpenChat also keeps model lists current by pulling live `/models` catalogs from supported providers and OpenRouter's public catalog.

No backend server, no account, no telemetry: the app talks directly to whichever provider you configure, and everything — API keys, chat history, memory, rules, skills — stays on your device.

## Why OpenChat

- **One app, every model** — compare and switch across providers without changing your workflow.
- **Always current** — live provider catalogs keep new models available as soon as the upstream provider exposes them.
- **No lock-in** — your chats and setup stay in OpenChat, while the model behind each conversation can change at any time.
- **Private by design** — API keys live in the iOS Keychain, chats are stored locally via SwiftData, and nothing is sent anywhere except the LLM provider you chose for that message.

## Features

- **Any provider, one app** — switch between OpenAI, Anthropic, Google Gemini, OpenRouter, Mistral AI, DeepSeek, Alibaba Cloud (Qwen), Moonshot AI (Kimi), Z.ai, 01.AI, or a self-hosted/custom OpenAI-compatible endpoint from the same chat UI.
- **Built for model choice** — use the best model for the job, keep the same interface, and move between providers without losing your workflow.
- **Web search** — attach a search provider (Tavily, Exa, Brave, Serper, SerpAPI) and let tool-capable models call it natively, or fall back to prompt injection for models without tool support.
- **Rules** — steer model behavior with global rules that apply everywhere, or per-chat rules scoped to a single conversation.
- **Memory** — the app can remember facts across chats; review, edit, pin, or delete anything it's stored at any time.
- **Skills** — define reusable prompts and invoke them instantly with a `/` slash command while composing a message.
- **Rich chat rendering** — Markdown, tables, syntax-highlighted code blocks, selectable message text, and image attachments (camera or photo library, for vision-capable models).

## Connecting a provider

On first launch, tap **Connect a Provider**, pick a provider, and paste in an API key. Add as many providers as you want, then choose the right model for each conversation.

Get keys here:

| Provider | Console |
|---|---|
| OpenAI | platform.openai.com |
| Anthropic | console.anthropic.com |
| OpenRouter | openrouter.ai |
| DeepSeek | platform.deepseek.com |
| Alibaba Cloud (Qwen) | bailian.console.aliyun.com |
| Moonshot AI (Kimi) | platform.moonshot.cn |
| Z.ai (GLM) | z.ai/model-api |
| Mistral AI | console.mistral.ai |
| Google | aistudio.google.com |

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

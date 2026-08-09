# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Dynamic reasoning configuration from provider model catalogs, with a separate brain-chip toggle for providers that expose a distinct thinking on/off parameter (OpenRouter `reasoning.enabled`, Anthropic `thinking`, DeepSeek `thinking.type`) and a ChatGPT-style effort gauge for providers that encode "off" as an effort level.
- Initial versioning and release workflow for OpenChat.

### Changed

- Replaced the custom Markdown renderer with SwiftStreamingMarkdown for cleaner, streaming-optimized assistant message rendering; removed the unused parser, syntax highlighter, and preview formatter.
- Tapping the "OpenChat" title in the history drawer now opens Settings, in addition to the existing gear icon.
- History drawer now transitions the settings and new-chat buttons into a single exit-search button when the search field is focused, and exits search mode when the drawer closes.
- The message composer now toggles focus with the chat/history view: the keyboard opens when the chat is visible and closes when the history drawer is open.
- History drawer now uses a push-style transition: the chat view slides out to the right as the drawer slides in, removing the overlap between the two views.
- History drawer no longer shows the vertical scroll indicator.

### Fixed

- Markdown heading spacing: section titles now get consistent top breathing room both inside text groups and when they follow code blocks, tables, or thematic breaks.
- Assistant replies with generated images now extract `<image>` / markdown data URI embeds and strip `{image}` placeholders so all images render instead of appearing as raw tags.
- OpenRouter model catalog context formatting now rounds millions-of-tokens display (e.g., "1M context") and capability inference tests reflect the current tool-call heuristics.
- CI unit tests now use ad-hoc signing so keychain-backed tests pass in the iOS simulator.
- Long model names in the chat header are now truncated with an ellipsis instead of pushing the layout.

### Removed

- Removed provider logos from the chat history drawer rows; chat titles are now shown without a provider icon.
- Removed the "Select text" chip from assistant responses; text selection remains available via the user-message context menu.

## [1.0.0] - 2026-08-07

### Added

- Initial release of OpenChat: native iOS chat app for OpenAI, Claude, Gemini, OpenRouter, DeepSeek, Qwen, Kimi/Moonshot, Z.ai GLM, 01.AI, and any custom OpenAI-compatible endpoint.
- On-device storage for API keys (Keychain), chat history, rules, memory, and skills.
- Web search integration (Tavily, Exa, Brave, Serper, SerpAPI) with tool support.
- Global and per-chat rules, memory management, and slash-command skills.
- Markdown, tables, syntax-highlighted code blocks, selectable text, and image attachments.

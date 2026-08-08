# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Dynamic reasoning configuration from provider model catalogs, with a separate brain-chip toggle for providers that expose a distinct thinking on/off parameter (OpenRouter `reasoning.enabled`, Anthropic `thinking`, DeepSeek `thinking.type`) and a ChatGPT-style effort gauge for providers that encode "off" as an effort level.
- Initial versioning and release workflow for OpenChat.

### Fixed

- OpenRouter model catalog context formatting now rounds millions-of-tokens display (e.g., "1M context") and capability inference tests reflect the current tool-call heuristics.
- CI unit tests now use ad-hoc signing so keychain-backed tests pass in the iOS simulator.

### Removed

- Removed the "Select text" chip from assistant responses; text selection remains available via the user-message context menu.

## [1.0.0] - 2026-08-07

### Added

- Initial release of OpenChat: native iOS chat app for OpenAI, Claude, Gemini, OpenRouter, DeepSeek, Qwen, Kimi/Moonshot, Z.ai GLM, 01.AI, and any custom OpenAI-compatible endpoint.
- On-device storage for API keys (Keychain), chat history, rules, memory, and skills.
- Web search integration (Tavily, Exa, Brave, Serper, SerpAPI) with tool support.
- Global and per-chat rules, memory management, and slash-command skills.
- Markdown, tables, syntax-highlighted code blocks, selectable text, and image attachments.

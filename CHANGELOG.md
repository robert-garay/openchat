# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Background assistant-response generation that survives leaving a chat and backgrounding the app, with a Dynamic Island Live Activity, a local notification on completion, and unread-response markers in the chat history list.
- Dynamic reasoning configuration from provider model catalogs, with a separate brain-chip toggle for providers that expose a distinct thinking on/off parameter (OpenRouter `reasoning.enabled`, Anthropic `thinking`, DeepSeek `thinking.type`) and a ChatGPT-style effort gauge for providers that encode "off" as an effort level.
- Initial versioning and release workflow for OpenChat.

### Changed

- Simplified the temporary chat ghost icon eyes to small dots matching the outline color, making it look less like an exact Pac-Man ghost.
- Removed the subtitle under the temporary chat banner that said "This chat won't appear in history."
- Replaced the custom Markdown renderer with SwiftStreamingMarkdown for cleaner, streaming-optimized assistant message rendering; removed the unused parser, syntax highlighter, and preview formatter.
- Tapping the "OpenChat" title in the history drawer now opens Settings, in addition to the existing gear icon.
- History drawer now transitions the settings and new-chat buttons into a single exit-search button when the search field is focused, and exits search mode when the drawer closes.
- The message composer now toggles focus with the chat/history view: the keyboard opens when the chat is visible and closes when the history drawer is open.
- History drawer now uses a push-style transition: the chat view slides out to the right as the drawer slides in, removing the overlap between the two views.
- History drawer no longer shows the vertical scroll indicator.

### Fixed

- Fixed navigation arrow buttons and related circular toolbar icons in the chat and history drawer so they remain visible in both light and dark mode.
- Fixed selected conversation row highlight and history-drawer menu divider so they are visible in light mode.
- Markdown heading spacing: section titles now get consistent top breathing room both inside text groups and when they follow code blocks, tables, or thematic breaks.
- Assistant replies with generated images now extract `<image>` / markdown data URI embeds and strip `{image}` placeholders so all images render instead of appearing as raw tags.
- OpenRouter model catalog context formatting now rounds millions-of-tokens display and capability inference tests reflect the current tool-call heuristics.
- Keychain-backed tests now use an isolated per-test keychain service to prevent cross-test contamination and pass reliably under parallel, randomized execution.
- Fixed Swift 6 strict-concurrency build errors: removed `@MainActor` from `ChatViewModel.deinit`, marked observer tokens and the notification center `nonisolated(unsafe)`, and made `NotificationService` delegate methods `nonisolated`.
- Addressed review feedback for background response generation: guarded visible-conversation lifecycle in `ChatView`/`RootView`, validated notification payloads, preserved skill proposals across refreshes, converted `LiveActivityService` to an actor, and fixed the Live Activity extension bundle identifier.
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

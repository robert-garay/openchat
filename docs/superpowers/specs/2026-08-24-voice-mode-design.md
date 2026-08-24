# Voice Mode — Design

## Summary

Add a full-duplex, interruptible voice conversation mode to OpenChat, built
on OpenAI's Realtime API. Users tap a mic button in the chat composer to
enter a full-screen voice UI, speak naturally with barge-in support, and get
spoken replies with the same tool-calling capabilities (web search,
calendar, reminders, contacts, memory, skills) available in text chat.
Voice turns are written into the same `Conversation`/`ChatMessage` history
used by text chat, so a user can freely move between typing and talking
within one thread.

## Background

OpenChat currently has no audio/voice code anywhere in the app. It is a
SwiftUI + SwiftData iOS app (iPhone + iPad, iOS 17+) with no backend server.
Chat requests go through provider-specific clients
(`AnthropicClient`, `OpenAICompatibleClient`) selected via `ProviderStore`,
which already includes a built-in "openai" `ProviderTemplate`
(`OpenChat/Models/ProviderTemplate.swift`) — so a user who has configured an
OpenAI API key for text chat already has what voice mode needs.

Anthropic has no realtime speech-to-speech API, so full-duplex voice is
necessarily provider-specific. OpenAI's Realtime API (WebSocket) was chosen
as the first (only, for v1) provider: it performs server-side voice activity
detection (turn-taking/interruption), removing the need to build our own
VAD, and supports function calling with the same JSON-schema tool shape
already used by `ChatTool`.

The project's stated convention (`AGENTS.md`) is to avoid adding
dependencies unless explicitly required. A WebRTC-based integration was
considered and rejected for v1 in favor of `URLSessionWebSocketTask`, which
requires no new dependency and mirrors the existing `ServerSentEventStream`
pattern already used for text streaming.

## Scope

- A new `Services/Voice/` group: `RealtimeVoiceSession` (WebSocket protocol
  client), `VoiceAudioEngine` (mic capture / playback via `AVAudioEngine`),
  and `VoiceConversationController` (`@Observable` coordinator).
- A new `origin` field on `ChatMessage` (`.text` / `.voice`) so voice-origin
  messages can be visually distinguished in the transcript.
- Tool-call bridging: reuse the existing `ChatTool` catalog and existing
  tool-execution services (calendar, reminders, contacts, memory, web
  search, skills) from voice sessions.
- New UI: a mic button in `MessageComposerView`, and a full-screen
  `VoiceModeView` (orb/waveform, live partial transcript caption, mute, end
  call, connection/tool-call state).
- Mic permission handling, `AVAudioSession` interruption handling, and
  reconnect-on-drop using the existing `NetworkMonitor`/`NetworkRetrier`.
- Unit tests for realtime event parsing and controller transcript/tool
  routing logic, using fixture payloads (no live network/audio in tests).

### Out of scope

- Any provider other than OpenAI (e.g. Gemini Live) — may be a future
  iteration behind the same `RealtimeVoiceSession`-shaped abstraction, but
  no abstraction is built preemptively for it now (YAGNI).
- WebRTC transport.
- macOS/other platforms — OpenChat targets iOS only (`project.yml`,
  `TARGETED_DEVICE_FAMILY: "1,2"`).
- Background/lock-screen voice sessions (session is expected to run
  foregrounded, in the full-screen `VoiceModeView`).
- A standalone "voice session" record/model — voice turns are ordinary
  `ChatMessage`s in the existing `Conversation`.

## Architecture

Three new components, layered like the existing chat stack
(`ChatCompletionClient` → `ChatViewModel`):

- **`RealtimeVoiceSession`** owns one `URLSessionWebSocketTask` connected to
  `wss://api.openai.com/v1/realtime`, authenticated with the OpenAI API key
  read from `ProviderStore`/`KeychainStore`. On connect it sends
  `session.update` with the model, voice, system instructions, and the
  serialized `ChatTool` catalog. It exposes an `AsyncStream<RealtimeEvent>`
  (a small enum: `.audioDelta`, `.transcriptDelta`, `.transcriptDone`,
  `.functionCallArguments`, `.responseDone`, `.error`, ...) built by parsing
  incoming WebSocket text frames, and accepts outbound audio chunks
  (`input_audio_buffer.append`) and function-call results
  (`conversation.item.create` + `response.create`). This mirrors how
  `ServerSentEventStream` is consumed today for text streaming.
- **`VoiceAudioEngine`** wraps `AVAudioEngine`. It configures
  `AVAudioSession` for voice chat (category/mode, speaker/earpiece/Bluetooth
  routing), installs a tap on the input node to capture mic audio, converts
  it to 24kHz mono PCM16, and forwards chunks to the session. On playback it
  schedules PCM buffers received from the session onto a player node, and
  exposes live input/output amplitude levels for the waveform UI.
- **`VoiceConversationController`** (`@Observable`) is the view-facing
  coordinator, analogous to `ChatViewModel`. It owns a
  `RealtimeVoiceSession` + `VoiceAudioEngine` pair, consumes the event
  stream, buffers in-progress partial transcripts, commits finished
  utterances as `ChatMessage`s, dispatches function calls to existing tool
  services, and publishes connection/listening/speaking/tool-call state for
  `VoiceModeView`.

## Conversation integration & data model

Voice mode attaches to whatever `Conversation` is currently open in
`ChatView`. On session start, `VoiceConversationController` builds the same
message-history context `ChatViewModel` would send for a text turn, so the
model has continuity with prior typed messages.

- `ChatMessage` gains an `origin` property (`.text` default / `.voice`) so
  the existing bubble UI can show a small indicator on voice-originated
  messages without otherwise changing rendering.
- Streaming partial transcript deltas are held in-memory on
  `VoiceConversationController`, not written to SwiftData. Once an
  utterance finalizes (`response.done` / the corresponding
  `conversation.item` completion event), it is committed as one
  `ChatMessage` — avoiding a flood of partial SwiftData writes during
  speech.
- There is no separate "voice session" record. Ending the call just tears
  down the WebSocket and audio engine; the conversation is simply more
  `ChatMessage`s in the same `Conversation`, so returning to the text
  composer continues the same thread naturally.

## Tool integration

The existing `ChatTool` catalog (`OpenChat/Services/ChatTool.swift`) is
already the provider-agnostic tool definition serialized for
`AnthropicClient`/`OpenAICompatibleClient` requests. `RealtimeVoiceSession`
serializes the same `ChatTool` set into `session.update.tools` — no
duplicate tool-schema code.

When the Realtime API emits `response.function_call_arguments.done`,
`VoiceConversationController` dispatches to the same tool-execution
services `ChatViewModel` already uses (`CalendarActionParser`,
`RemindersWriter`, `ContactsWriter`, `WebSearchService`, `MemoryStore`,
`SkillToolService`, etc.), then returns the result via
`conversation.item.create` (`function_call_output`) followed by
`response.create`, per the Realtime API's function-calling protocol.

Tool actions that normally require an interactive confirmation sheet in
text chat (e.g. rule/proposal creation) are not blocked on a modal while
mid-call; instead the controller surfaces a brief spoken/visual prompt
("I'll remember that you prefer X — sound good?") and proceeds on verbal
confirmation, since a modal sheet does not fit a spoken-conversation flow.

## UI

- `MessageComposerView` gets a new mic icon alongside its existing
  attachment/skill controls. Tapping it presents `VoiceModeView` as a
  full-screen cover over `ChatView`.
- `VoiceModeView` is a visually distinct, immersive screen (OpenChat's
  `DesignSystem`, not matching the chat list styling): a large
  amplitude-reactive orb/waveform driven by `VoiceAudioEngine`'s live audio
  levels, a live-updating caption of the current partial transcript, a mute
  toggle, and an end-call button.
- Explicit states surfaced in the UI: connecting, listening, model
  speaking, tool-call in progress (e.g. "Checking your calendar…"), muted,
  and reconnecting-after-drop.
- Dismissing `VoiceModeView` ends the session (closes the WebSocket, stops
  the audio engine) and returns to `ChatView`, which now shows the
  committed voice-origin messages inline in the transcript.

## Error handling & permissions

- Mic permission (`AVAudioApplication.requestRecordPermission`) is
  requested on first use, with a clear pre-permission explanation and a
  Settings deep-link if previously denied.
- A dropped WebSocket triggers one silent reconnect attempt (re-sending
  `session.update` to restore instructions/tools/context) using the
  existing `NetworkMonitor`/`NetworkRetrier` machinery, before surfacing a
  visible reconnect-failed state in `VoiceModeView`.
- `AVAudioSession` interruptions (phone call, Siri, route change) pause
  capture/playback and attempt to resume once the interruption ends; if
  resume fails, the session ends gracefully and the transcript up to that
  point is still saved as `ChatMessage`s.
- Missing/invalid OpenAI API key or quota errors are checked when the mic
  button is tapped, before opening the audio session — surfaced as an
  inline error rather than a failed connection after the screen opens.

## Testing

- Unit tests for `RealtimeVoiceSession` event parsing (raw JSON frames →
  `RealtimeEvent`) using recorded fixture payloads, in the same style as
  the existing `AnthropicClient+WireTypes`/`OpenAICompatibleClient+WireTypes`
  tests. No live network calls in unit tests.
- Unit tests for `VoiceConversationController` using a mock
  session/audio-engine (protocol-backed), covering: partial-transcript
  buffering, commit-to-`ChatMessage` on utterance completion, and
  function-call dispatch/response routing.
- Audio engine behavior (mic capture, playback routing, interruption
  recovery) is verified manually on a real device — not meaningfully
  unit-testable, consistent with the project's existing convention of
  manual verification for UI/audio-adjacent work.

## Open questions / follow-ups (explicitly out of scope for this spec)

- Whether to add a second realtime provider (e.g. Gemini Live) later, and
  whether `RealtimeVoiceSession` needs to become a protocol at that point.
- Whether voice mode should ever support background/lock-screen operation.

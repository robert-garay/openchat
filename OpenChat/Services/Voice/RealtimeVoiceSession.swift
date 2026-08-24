import Foundation

/// Owns one OpenAI Realtime API WebSocket connection. Talks in raw event
/// `Data` via `RealtimeVoiceTransport` and exposes decoded domain events.
/// Mirrors how `ServerSentEventStream` is consumed for text chat, but
/// bidirectional: callers also push audio/tool-result events back in.
actor RealtimeVoiceSession {
    private let transport: any RealtimeVoiceTransport
    private let endpoint: URL

    init(
        transport: any RealtimeVoiceTransport = URLSessionRealtimeTransport(),
        endpoint: URL = URL(string: "wss://api.openai.com/v1/realtime")!
    ) {
        self.transport = transport
        self.endpoint = endpoint
    }

    /// Connects, configures the session (voice, instructions, tools), and
    /// returns a stream of decoded server events. The stream finishes when
    /// the connection closes or fails.
    func connect(
        apiKey: String,
        model: String,
        voice: String,
        instructions: String,
        tools: [ChatToolDefinition]
    ) async throws -> AsyncThrowingStream<RealtimeVoiceEvent, Error> {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw RealtimeVoiceError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        guard let url = components.url else { throw RealtimeVoiceError.invalidURL }

        try await transport.connect(url: url, apiKey: apiKey)

        let rawFrames = transport.receive()
        let events = AsyncThrowingStream<RealtimeVoiceEvent, Error> { continuation in
            let forwardingTask = Task {
                do {
                    for try await frame in rawFrames {
                        if let event = RealtimeVoiceEvent.parse(frame) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in forwardingTask.cancel() }
        }

        try await transport.send(
            RealtimeVoiceOutbound.sessionUpdate(instructions: instructions, voice: voice, tools: tools)
        )

        return events
    }

    /// Streams one chunk of mic audio (24kHz mono PCM16) to the server.
    func appendAudio(_ pcm16: Data) async throws {
        try await transport.send(RealtimeVoiceOutbound.appendAudio(pcm16))
    }

    /// Returns a tool's result to the model and asks it to continue the turn.
    func sendFunctionCallOutput(callID: String, output: String) async throws {
        try await transport.send(RealtimeVoiceOutbound.functionCallOutput(callID: callID, output: output))
        try await transport.send(RealtimeVoiceOutbound.responseCreate())
    }

    func close() async {
        await transport.close()
    }
}

import Foundation

/// Domain-level events consumed by `VoiceConversationController`, decoded from
/// OpenAI Realtime API server events (`wss://api.openai.com/v1/realtime`).
/// Event types not modeled here are parsed as `.unknown` and ignored by callers.
enum RealtimeVoiceEvent: Equatable, Sendable {
    /// The user has started / stopped speaking, per server-side VAD.
    case inputSpeechStarted
    case inputSpeechStopped
    /// Incremental transcript of what the user said (Whisper transcription of mic audio).
    case inputTranscriptCompleted(String)
    /// Incremental transcript of the assistant's spoken reply.
    case outputTranscriptDelta(String)
    case outputTranscriptDone(String)
    /// Base64-decoded PCM16 audio chunk for the assistant's spoken reply.
    case outputAudioDelta(Data)
    case outputAudioDone
    /// A function-call item has started; arguments arrive incrementally afterward.
    case functionCallStarted(callID: String, name: String)
    case functionCallArgumentsDone(callID: String, arguments: String)
    /// One assistant turn (text + audio + any function calls) has finished.
    case responseDone
    case error(String)
    case unknown(type: String)

    static func parse(_ data: Data) -> RealtimeVoiceEvent? {
        guard let envelope = try? JSONDecoder().decode(RealtimeWireEnvelope.self, from: data) else {
            return nil
        }

        switch envelope.type {
        case "input_audio_buffer.speech_started":
            return .inputSpeechStarted
        case "input_audio_buffer.speech_stopped":
            return .inputSpeechStopped
        case "conversation.item.input_audio_transcription.completed":
            return .inputTranscriptCompleted(envelope.transcript ?? "")
        case "response.audio_transcript.delta":
            return .outputTranscriptDelta(envelope.delta ?? "")
        case "response.audio_transcript.done":
            return .outputTranscriptDone(envelope.transcript ?? "")
        case "response.audio.delta":
            guard let delta = envelope.delta, let audio = Data(base64Encoded: delta) else { return nil }
            return .outputAudioDelta(audio)
        case "response.audio.done":
            return .outputAudioDone
        case "response.output_item.added":
            guard let item = envelope.item, item.type == "function_call",
                  let callID = item.callID, let name = item.name else {
                return .unknown(type: envelope.type)
            }
            return .functionCallStarted(callID: callID, name: name)
        case "response.function_call_arguments.done":
            guard let callID = envelope.callID else { return .unknown(type: envelope.type) }
            return .functionCallArgumentsDone(callID: callID, arguments: envelope.arguments ?? "{}")
        case "response.done":
            return .responseDone
        case "error":
            return .error(envelope.error?.message ?? "Unknown realtime error")
        default:
            return .unknown(type: envelope.type)
        }
    }
}

/// Loose envelope covering every server event shape this app reads from.
/// Fields absent from a given event type simply decode as `nil`.
struct RealtimeWireEnvelope: Decodable {
    var type: String
    var delta: String?
    var transcript: String?
    var callID: String?
    var arguments: String?
    var item: Item?
    var error: WireError?

    enum CodingKeys: String, CodingKey {
        case type, delta, transcript, item, error, arguments
        case callID = "call_id"
    }

    struct Item: Decodable {
        var type: String?
        var name: String?
        var callID: String?

        enum CodingKeys: String, CodingKey {
            case type, name
            case callID = "call_id"
        }
    }

    struct WireError: Decodable {
        var message: String?
    }
}

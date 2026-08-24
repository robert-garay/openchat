import Foundation

/// Builds client -> server event payloads for the OpenAI Realtime API.
enum RealtimeVoiceOutbound {
    static func sessionUpdate(
        instructions: String,
        voice: String,
        tools: [ChatToolDefinition]
    ) throws -> Data {
        let payload = SessionUpdateEvent(session: SessionConfig(instructions: instructions, voice: voice, tools: tools.map(ToolPayload.init)))
        return try JSONEncoder().encode(payload)
    }

    static func appendAudio(_ pcm16: Data) throws -> Data {
        try JSONEncoder().encode(InputAudioBufferAppendEvent(audio: pcm16.base64EncodedString()))
    }

    static func functionCallOutput(callID: String, output: String) throws -> Data {
        try JSONEncoder().encode(
            ConversationItemCreateEvent(item: FunctionCallOutputItem(callID: callID, output: output))
        )
    }

    static func responseCreate() throws -> Data {
        try JSONEncoder().encode(ResponseCreateEvent())
    }

    // MARK: - Wire types

    private struct SessionUpdateEvent: Encodable {
        let type = "session.update"
        var session: SessionConfig
    }

    private struct SessionConfig: Encodable {
        let modalities = ["audio", "text"]
        var instructions: String
        var voice: String
        let inputAudioFormat = "pcm16"
        let outputAudioFormat = "pcm16"
        var inputAudioTranscription = InputAudioTranscription()
        let turnDetection = TurnDetection()
        var tools: [ToolPayload]
        let toolChoice = "auto"

        enum CodingKeys: String, CodingKey {
            case modalities, instructions, voice, tools
            case inputAudioFormat = "input_audio_format"
            case outputAudioFormat = "output_audio_format"
            case inputAudioTranscription = "input_audio_transcription"
            case turnDetection = "turn_detection"
            case toolChoice = "tool_choice"
        }
    }

    private struct InputAudioTranscription: Encodable {
        let model = "whisper-1"
    }

    private struct TurnDetection: Encodable {
        let type = "server_vad"
    }

    private struct ToolPayload: Encodable {
        let type = "function"
        var name: String
        var description: String
        var parameters: AnyCodableJSON

        init(_ definition: ChatToolDefinition) {
            name = definition.name
            description = definition.description
            let object = (try? JSONSerialization.jsonObject(with: Data(definition.parametersJSON.utf8))) ?? [String: Any]()
            parameters = AnyCodableJSON(object)
        }
    }

    private struct InputAudioBufferAppendEvent: Encodable {
        let type = "input_audio_buffer.append"
        var audio: String
    }

    private struct ConversationItemCreateEvent: Encodable {
        let type = "conversation.item.create"
        var item: FunctionCallOutputItem
    }

    private struct FunctionCallOutputItem: Encodable {
        let type = "function_call_output"
        var callID: String
        var output: String

        enum CodingKeys: String, CodingKey {
            case type, output
            case callID = "call_id"
        }
    }

    private struct ResponseCreateEvent: Encodable {
        let type = "response.create"
    }
}

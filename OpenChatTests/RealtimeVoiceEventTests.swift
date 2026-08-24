import Foundation
import Testing
@testable import OpenChat

struct RealtimeVoiceEventTests {
    @Test("parses speech started / stopped")
    func parsesSpeechLifecycle() {
        #expect(RealtimeVoiceEvent.parse(Data(#"{"type":"input_audio_buffer.speech_started"}"#.utf8)) == .inputSpeechStarted)
        #expect(RealtimeVoiceEvent.parse(Data(#"{"type":"input_audio_buffer.speech_stopped"}"#.utf8)) == .inputSpeechStopped)
    }

    @Test("parses user transcript completion")
    func parsesInputTranscript() {
        let json = #"{"type":"conversation.item.input_audio_transcription.completed","transcript":"Hello there"}"#
        #expect(RealtimeVoiceEvent.parse(Data(json.utf8)) == .inputTranscriptCompleted("Hello there"))
    }

    @Test("parses assistant transcript delta and done")
    func parsesOutputTranscript() {
        let delta = #"{"type":"response.audio_transcript.delta","delta":"Hi "}"#
        #expect(RealtimeVoiceEvent.parse(Data(delta.utf8)) == .outputTranscriptDelta("Hi "))

        let done = #"{"type":"response.audio_transcript.done","transcript":"Hi there"}"#
        #expect(RealtimeVoiceEvent.parse(Data(done.utf8)) == .outputTranscriptDone("Hi there"))
    }

    @Test("decodes base64 audio deltas, drops undecodable ones")
    func parsesAudioDelta() {
        let payload = Data("hello-audio".utf8).base64EncodedString()
        let json = #"{"type":"response.audio.delta","delta":"\#(payload)"}"#
        #expect(RealtimeVoiceEvent.parse(Data(json.utf8)) == .outputAudioDelta(Data("hello-audio".utf8)))

        let invalid = #"{"type":"response.audio.delta","delta":"not base64!!"}"#
        #expect(RealtimeVoiceEvent.parse(Data(invalid.utf8)) == nil)
    }

    @Test("parses function call lifecycle")
    func parsesFunctionCall() {
        let started = """
        {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_1","name":"web_search"}}
        """
        #expect(RealtimeVoiceEvent.parse(Data(started.utf8)) == .functionCallStarted(callID: "call_1", name: "web_search"))

        let done = #"{"type":"response.function_call_arguments.done","call_id":"call_1","arguments":"{\"query\":\"weather\"}"}"#
        #expect(
            RealtimeVoiceEvent.parse(Data(done.utf8))
                == .functionCallArgumentsDone(callID: "call_1", arguments: #"{"query":"weather"}"#)
        )
    }

    @Test("non function-call output items are unknown")
    func ignoresNonFunctionCallItems() {
        let json = #"{"type":"response.output_item.added","item":{"type":"message"}}"#
        #expect(RealtimeVoiceEvent.parse(Data(json.utf8)) == .unknown(type: "response.output_item.added"))
    }

    @Test("parses response.done and errors")
    func parsesTerminalEvents() {
        #expect(RealtimeVoiceEvent.parse(Data(#"{"type":"response.done"}"#.utf8)) == .responseDone)

        let error = #"{"type":"error","error":{"message":"boom"}}"#
        #expect(RealtimeVoiceEvent.parse(Data(error.utf8)) == .error("boom"))
    }

    @Test("unrecognized types fall back to unknown, malformed JSON to nil")
    func parsesFallbacks() {
        #expect(RealtimeVoiceEvent.parse(Data(#"{"type":"session.created"}"#.utf8)) == .unknown(type: "session.created"))
        #expect(RealtimeVoiceEvent.parse(Data("not json".utf8)) == nil)
    }
}

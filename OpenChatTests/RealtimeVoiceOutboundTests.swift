import Foundation
import Testing
@testable import OpenChat

struct RealtimeVoiceOutboundTests {
    @Test("session.update embeds instructions, voice, and tool schemas")
    func sessionUpdatePayload() throws {
        let tool = ChatToolDefinition(
            name: "web_search",
            description: "Search the web",
            parametersJSON: #"{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}"#
        )
        let data = try RealtimeVoiceOutbound.sessionUpdate(instructions: "Be concise", voice: "alloy", tools: [tool])
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["type"] as? String == "session.update")
        let session = try #require(json["session"] as? [String: Any])
        #expect(session["instructions"] as? String == "Be concise")
        #expect(session["voice"] as? String == "alloy")
        #expect(session["input_audio_format"] as? String == "pcm16")
        #expect(session["output_audio_format"] as? String == "pcm16")

        let tools = try #require(session["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["type"] as? String == "function")
        #expect(tools[0]["name"] as? String == "web_search")
        let parameters = try #require(tools[0]["parameters"] as? [String: Any])
        #expect(parameters["type"] as? String == "object")
    }

    @Test("appendAudio base64-encodes the PCM16 payload")
    func appendAudioPayload() throws {
        let pcm = Data([0x01, 0x02, 0x03, 0x04])
        let data = try RealtimeVoiceOutbound.appendAudio(pcm)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["type"] as? String == "input_audio_buffer.append")
        #expect(json["audio"] as? String == pcm.base64EncodedString())
    }

    @Test("functionCallOutput nests a function_call_output item")
    func functionCallOutputPayload() throws {
        let data = try RealtimeVoiceOutbound.functionCallOutput(callID: "call_1", output: "42 degrees")
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["type"] as? String == "conversation.item.create")
        let item = try #require(json["item"] as? [String: Any])
        #expect(item["type"] as? String == "function_call_output")
        #expect(item["call_id"] as? String == "call_1")
        #expect(item["output"] as? String == "42 degrees")
    }

    @Test("responseCreate is a bare type payload")
    func responseCreatePayload() throws {
        let data = try RealtimeVoiceOutbound.responseCreate()
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["type"] as? String == "response.create")
    }
}

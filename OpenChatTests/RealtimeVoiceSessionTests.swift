import Foundation
import Testing
@testable import OpenChat

struct RealtimeVoiceSessionTests {
    @Test("connect authenticates, targets the given model, and sends session.update")
    func connectConfiguresSession() async throws {
        let transport = FakeRealtimeVoiceTransport()
        let session = RealtimeVoiceSession(
            transport: transport,
            endpoint: URL(string: "wss://example.com/v1/realtime")!
        )

        _ = try await session.connect(
            apiKey: "sk-test",
            model: "gpt-4o-realtime-preview",
            voice: "alloy",
            instructions: "Be concise",
            tools: []
        )

        let url = await transport.connectedURL
        #expect(url?.absoluteString == "wss://example.com/v1/realtime?model=gpt-4o-realtime-preview")
        let apiKey = await transport.connectedAPIKey
        #expect(apiKey == "sk-test")

        let firstPayload = await transport.sentPayloadData(at: 0)?.jsonObject
        #expect(firstPayload?["type"] as? String == "session.update")
    }

    @Test("decoded server frames surface as events on the returned stream")
    func connectStreamsDecodedEvents() async throws {
        let transport = FakeRealtimeVoiceTransport()
        let session = RealtimeVoiceSession(transport: transport)

        let events = try await session.connect(
            apiKey: "sk-test",
            model: "gpt-4o-realtime-preview",
            voice: "alloy",
            instructions: "",
            tools: []
        )

        await transport.simulateReceive(#"{"type":"response.done"}"#)
        await transport.simulateFinish()

        var received: [RealtimeVoiceEvent] = []
        for try await event in events {
            received.append(event)
        }
        #expect(received == [.responseDone])
    }

    @Test("appendAudio forwards a base64 input_audio_buffer.append event")
    func appendAudioForwards() async throws {
        let transport = FakeRealtimeVoiceTransport()
        let session = RealtimeVoiceSession(transport: transport)
        _ = try await session.connect(apiKey: "k", model: "m", voice: "alloy", instructions: "", tools: [])

        try await session.appendAudio(Data([1, 2, 3]))

        let payload = await transport.sentPayloadData(at: 1)?.jsonObject
        #expect(payload?["type"] as? String == "input_audio_buffer.append")
    }

    @Test("sendFunctionCallOutput sends the tool result then asks for a response")
    func sendFunctionCallOutputSendsTwoEvents() async throws {
        let transport = FakeRealtimeVoiceTransport()
        let session = RealtimeVoiceSession(transport: transport)
        _ = try await session.connect(apiKey: "k", model: "m", voice: "alloy", instructions: "", tools: [])

        try await session.sendFunctionCallOutput(callID: "call_1", output: "42 degrees")

        let outputPayload = await transport.sentPayloadData(at: 1)?.jsonObject
        #expect(outputPayload?["type"] as? String == "conversation.item.create")
        let responsePayload = await transport.sentPayloadData(at: 2)?.jsonObject
        #expect(responsePayload?["type"] as? String == "response.create")
    }

    @Test("close tears down the transport")
    func closeClosesTransport() async throws {
        let transport = FakeRealtimeVoiceTransport()
        let session = RealtimeVoiceSession(transport: transport)
        _ = try await session.connect(apiKey: "k", model: "m", voice: "alloy", instructions: "", tools: [])

        await session.close()

        let closeCount = await transport.closeCallCount
        #expect(closeCount == 1)
    }
}

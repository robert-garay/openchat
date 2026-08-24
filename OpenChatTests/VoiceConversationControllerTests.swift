import Foundation
import SwiftData
import Testing
@testable import OpenChat

@MainActor
struct VoiceConversationControllerTests {
    private struct Environment {
        let controller: VoiceConversationController
        let transport: FakeRealtimeVoiceTransport
        let audioEngine: FakeVoiceAudioEngine
        let conversation: Conversation
        let modelContext: ModelContext
        let skillsStore: SkillsStore
    }

    private static func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, MemoryItem.self, RuleItem.self, Skill.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Fully wired environment: OpenAI configured with an API key, fake transport/audio engine.
    private static func makeEnvironment() throws -> Environment {
        let suiteID = UUID().uuidString
        KeychainStore.service = "com.openchat.tests.voice.\(suiteID)"
        KeychainStore.removeAll()

        let providerStore = ProviderStore(defaults: UserDefaults(suiteName: "com.openchat.tests.voice.providers.\(suiteID)")!)
        let template = try #require(ProviderTemplate.template(for: "openai"))
        providerStore.addFromTemplate(template)
        let provider = try #require(providerStore.provider(withID: "openai"))
        providerStore.setAPIKey("sk-test-key", for: provider)

        let webSearchStore = WebSearchStore(defaults: UserDefaults(suiteName: "com.openchat.tests.voice.search.\(suiteID)")!)
        let skillsStore = SkillsStore(defaults: UserDefaults(suiteName: "com.openchat.tests.voice.skills.\(suiteID)")!)
        let rulesStore = RulesStore(defaults: UserDefaults(suiteName: "com.openchat.tests.voice.rules.\(suiteID)")!)
        let memoryStore = MemoryStore(defaults: UserDefaults(suiteName: "com.openchat.tests.voice.memory.\(suiteID)")!)

        let modelContext = try makeModelContext()
        let conversation = Conversation(providerID: "anthropic", modelID: "claude", systemPrompt: "")
        modelContext.insert(conversation)

        let transport = FakeRealtimeVoiceTransport()
        let session = RealtimeVoiceSession(transport: transport)
        let audioEngine = FakeVoiceAudioEngine()

        let controller = VoiceConversationController(
            conversation: conversation,
            modelContext: modelContext,
            providerStore: providerStore,
            webSearchStore: webSearchStore,
            skillsStore: skillsStore,
            rulesStore: rulesStore,
            memoryStore: memoryStore,
            session: session,
            audioEngine: audioEngine
        )

        return Environment(
            controller: controller,
            transport: transport,
            audioEngine: audioEngine,
            conversation: conversation,
            modelContext: modelContext,
            skillsStore: skillsStore
        )
    }

    @Test("start fails inline when no OpenAI key is configured")
    func startFailsWithoutAPIKey() async throws {
        let suiteID = UUID().uuidString
        let providerStore = ProviderStore(defaults: UserDefaults(suiteName: "com.openchat.tests.voice.nokey.\(suiteID)")!)
        let webSearchStore = WebSearchStore(defaults: UserDefaults(suiteName: "com.openchat.tests.voice.nokey.search.\(suiteID)")!)
        let skillsStore = SkillsStore(defaults: UserDefaults(suiteName: "com.openchat.tests.voice.nokey.skills.\(suiteID)")!)
        let rulesStore = RulesStore(defaults: UserDefaults(suiteName: "com.openchat.tests.voice.nokey.rules.\(suiteID)")!)
        let memoryStore = MemoryStore(defaults: UserDefaults(suiteName: "com.openchat.tests.voice.nokey.memory.\(suiteID)")!)
        let modelContext = try Self.makeModelContext()
        let conversation = Conversation(providerID: "anthropic", modelID: "claude")
        modelContext.insert(conversation)
        let audioEngine = FakeVoiceAudioEngine()

        let controller = VoiceConversationController(
            conversation: conversation,
            modelContext: modelContext,
            providerStore: providerStore,
            webSearchStore: webSearchStore,
            skillsStore: skillsStore,
            rulesStore: rulesStore,
            memoryStore: memoryStore,
            audioEngine: audioEngine
        )

        await controller.start()

        #expect(controller.state == .failed("Add an OpenAI API key in Settings to use voice mode."))
        #expect(audioEngine.startCallCount == 0)
    }

    @Test("start connects and begins listening")
    func startConnectsSuccessfully() async throws {
        let env = try Self.makeEnvironment()
        await env.controller.start()

        #expect(env.controller.state == .listening)
        #expect(env.audioEngine.startCallCount == 1)
        let firstPayload = await env.transport.sentPayloadData(at: 0)?.jsonObject
        #expect(firstPayload?["type"] as? String == "session.update")

        await env.controller.end()
    }

    @Test("a completed user transcript is committed as a voice-origin ChatMessage")
    func commitsUserTranscript() async throws {
        let env = try Self.makeEnvironment()
        await env.controller.start()

        await env.transport.simulateReceive(
            #"{"type":"conversation.item.input_audio_transcription.completed","transcript":"What's the weather?"}"#
        )

        await waitUntil { env.conversation.sortedMessages.count == 1 }

        let message = try #require(env.conversation.sortedMessages.first)
        #expect(message.role == .user)
        #expect(message.content == "What's the weather?")
        #expect(message.origin == .voice)

        await env.controller.end()
    }

    @Test("assistant transcript is committed on response.done")
    func commitsAssistantTranscriptOnResponseDone() async throws {
        let env = try Self.makeEnvironment()
        await env.controller.start()

        await env.transport.simulateReceive(#"{"type":"response.audio_transcript.delta","delta":"It's sunny"}"#)
        await env.transport.simulateReceive(#"{"type":"response.done"}"#)

        await waitUntil { env.conversation.sortedMessages.count == 1 }

        let message = try #require(env.conversation.sortedMessages.first)
        #expect(message.role == .assistant)
        #expect(message.content == "It's sunny")
        #expect(message.origin == .voice)
        #expect(message.providerID == "openai")

        await env.controller.end()
    }

    @Test("invoke_skill function calls route to the matching stored skill")
    func dispatchesInvokeSkillFunctionCall() async throws {
        let env = try Self.makeEnvironment()
        env.skillsStore.setIsEnabled(true)
        let skill = Skill(name: "Trip Planner", slashName: "trip", instructions: "Plan trips.")
        env.modelContext.insert(skill)

        await env.controller.start()

        await env.transport.simulateReceive(
            #"{"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_1","name":"invoke_skill"}}"#
        )
        await env.transport.simulateReceive(
            #"{"type":"response.function_call_arguments.done","call_id":"call_1","arguments":"{\"slash_name\":\"trip\"}"}"#
        )

        await waitUntil { await env.transport.sentPayloads.count >= 3 }

        let outputPayload = await env.transport.sentPayloadData(at: 1)?.jsonObject
        #expect(outputPayload?["type"] as? String == "conversation.item.create")
        let item = try #require(outputPayload?["item"] as? [String: Any])
        let output = try #require(item["output"] as? String)
        #expect(output.contains("Plan trips."))

        let responsePayload = await env.transport.sentPayloadData(at: 2)?.jsonObject
        #expect(responsePayload?["type"] as? String == "response.create")

        await env.controller.end()
    }
}

/// Polls `condition` until it's true or the timeout elapses — needed because
/// realtime events are processed by a background `Task` forwarding from the
/// fake transport's stream.
@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: () async -> Bool
) async {
    let deadline = ContinuousClock().now + timeout
    while ContinuousClock().now < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Timed out waiting for condition")
}

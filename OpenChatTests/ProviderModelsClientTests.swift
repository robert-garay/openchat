import XCTest
@testable import OpenChat

final class ProviderModelsClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testDecodeOpenAIModelsFiltersNonChat() throws {
        let json = Data("""
        {
          "data": [
            { "id": "gpt-4o" },
            { "id": "o4-mini" },
            { "id": "whisper-1" },
            { "id": "text-embedding-3-large" },
            { "id": "dall-e-3" },
            { "id": "deepseek-chat" }
          ]
        }
        """.utf8)

        let models = try ProviderModelsClient.decodeOpenAIModels(from: json)
        XCTAssertEqual(models.map(\.id), ["gpt-4o", "o4-mini", "deepseek-chat"])
        XCTAssertEqual(models[0].capabilities, [.vision, .tools])
        XCTAssertEqual(models[1].capabilities, [.vision, .tools, .reasoning, .effort])
        XCTAssertEqual(models[2].capabilities, [.tools])
    }

    func testDecodeOpenAIModelsUsesArchitectureMetadataWhenPresent() throws {
        let json = Data("""
        {
          "data": [
            {
              "id": "custom/text-only",
              "architecture": {
                "input_modalities": ["text"],
                "output_modalities": ["text"]
              },
              "supported_parameters": ["temperature"]
            },
            {
              "id": "custom/vision-tools",
              "architecture": {
                "input_modalities": ["text", "image"],
                "output_modalities": ["text"]
              },
              "supported_parameters": ["tools"]
            }
          ]
        }
        """.utf8)

        let models = try ProviderModelsClient.decodeOpenAIModels(from: json)
        XCTAssertEqual(models[0].capabilities, [])
        XCTAssertEqual(models[1].capabilities, [.vision, .tools])
    }

    func testDecodeAnthropicModelsMapsCapabilities() throws {
        let json = Data("""
        {
          "data": [
            {
              "id": "claude-opus-4-6",
              "display_name": "Claude Opus 4.6",
              "max_input_tokens": 200000,
              "capabilities": {
                "image_input": { "supported": true },
                "pdf_input": { "supported": true },
                "thinking": { "supported": true }
              }
            }
          ],
          "has_more": false,
          "last_id": "claude-opus-4-6"
        }
        """.utf8)

        let page = try ProviderModelsClient.decodeAnthropicModels(from: json)
        XCTAssertEqual(page.models.count, 1)
        let model = page.models[0]
        XCTAssertEqual(model.id, "claude-opus-4-6")
        XCTAssertEqual(model.displayName, "Claude Opus 4.6")
        XCTAssertEqual(model.subtitle, "200K context")
        XCTAssertEqual(model.capabilities, [.vision, .files, .tools, .reasoning])
        XCTAssertFalse(page.hasMore)
    }

    func testDecodeAnthropicModelsInfersWhenCapabilitiesMissing() throws {
        let json = Data("""
        {
          "data": [
            {
              "id": "claude-sonnet-4-6",
              "display_name": "Claude Sonnet 4.6",
              "max_input_tokens": 200000
            }
          ],
          "has_more": false
        }
        """.utf8)

        let page = try ProviderModelsClient.decodeAnthropicModels(from: json)
        XCTAssertEqual(page.models[0].capabilities, [.vision, .tools])
    }

    func testEnrichMergesCapabilitiesAndPrefersTemplateLabels() {
        let live = [
            AIModel(id: "gpt-5", displayName: "gpt-5", capabilities: [.reasoning]),
            AIModel(id: "mystery-model", displayName: "mystery-model", capabilities: [.tools])
        ]
        let defaults = [
            AIModel(id: "gpt-5", displayName: "GPT-5", subtitle: "Flagship model", capabilities: [.vision, .tools])
        ]

        let enriched = ProviderModelsClient.enrich(live, using: defaults)
        XCTAssertEqual(enriched[0].displayName, "GPT-5")
        XCTAssertEqual(enriched[0].subtitle, "Flagship model")
        XCTAssertEqual(enriched[0].capabilities, [.vision, .tools, .reasoning])
        XCTAssertEqual(enriched[1].displayName, "mystery-model")
        XCTAssertEqual(enriched[1].capabilities, [.tools])
    }

    func testIsLikelyChatModelID() {
        XCTAssertTrue(ProviderModelsClient.isLikelyChatModelID("gpt-4o-mini"))
        XCTAssertTrue(ProviderModelsClient.isLikelyChatModelID("claude-sonnet-4"))
        XCTAssertFalse(ProviderModelsClient.isLikelyChatModelID("whisper-1"))
        XCTAssertFalse(ProviderModelsClient.isLikelyChatModelID("text-embedding-3-small"))
    }

    func testIsLikelyRealtimeVoiceModelID() {
        XCTAssertTrue(ProviderModelsClient.isLikelyRealtimeVoiceModelID("gpt-4o-realtime-preview"))
        XCTAssertTrue(ProviderModelsClient.isLikelyRealtimeVoiceModelID("gpt-4o-mini-realtime-preview"))
        XCTAssertFalse(ProviderModelsClient.isLikelyRealtimeVoiceModelID("gpt-4o-mini"))
        XCTAssertFalse(ProviderModelsClient.isLikelyRealtimeVoiceModelID("gpt-4o-transcribe"))
        XCTAssertFalse(ProviderModelsClient.isLikelyRealtimeVoiceModelID("whisper-1"))
    }

    func testDecodeRealtimeVoiceModelsFiltersAndSorts() throws {
        let json = Data("""
        {
          "data": [
            { "id": "gpt-4o" },
            { "id": "gpt-4o-realtime-preview" },
            { "id": "whisper-1" },
            { "id": "gpt-4o-mini-realtime-preview" },
            { "id": "gpt-4o-transcribe" }
          ]
        }
        """.utf8)

        let models = try ProviderModelsClient.decodeRealtimeVoiceModels(from: json)
        XCTAssertEqual(models.map(\.id), ["gpt-4o-mini-realtime-preview", "gpt-4o-realtime-preview"])
        XCTAssertEqual(models[0].displayName, "gpt-4o-mini-realtime-preview")
    }

    func testOpenCodeDecodeKeepsOnlyChatCompletionsModels() throws {
        let json = Data("""
        {
          "data": [
            { "id": "deepseek-v4.1-flash", "api": { "chat-completions": {} } },
            { "id": "gpt-5.6-luna", "api": { "responses": {} } },
            { "id": "claude-sonnet-4-6", "api": { "messages": {} } },
            { "id": "gemini-4-argon", "api": { "generate-content": {} } }
          ]
        }
        """.utf8)

        let all = try ProviderModelsClient.decodeOpenAIModels(from: json)
        XCTAssertEqual(all.map(\.id).count, 4)

        let chatOnly = try ProviderModelsClient.decodeOpenAIModels(
            from: json,
            requiresChatCompletionsAPI: true
        )
        XCTAssertEqual(chatOnly.map(\.id), ["deepseek-v4.1-flash"])
    }

    func testFetchModelsSendsCustomHeaders() async throws {
        MockURLProtocol.enqueue(json: #"{"data":[{"id":"deepseek-v4.1-flash"}]}"#)

        let provider = ConfiguredProvider(
            id: "opencode-go",
            templateID: "opencode-go",
            name: "OpenCode Go",
            symbolName: "chevron.left.forwardslash.chevron.right",
            tint: "#2563EB",
            baseURL: "https://example.com/v1",
            apiFormat: .openAI,
            models: [],
            requiresAPIKey: true,
            isEnabled: true,
            customHeaders: ["x-opencode-session": "session-123"]
        )

        let client = ProviderModelsClient(session: makeSession())
        let models = try await client.fetchModels(for: provider, apiKey: "sk-test")

        XCTAssertEqual(models.map(\.id), ["deepseek-v4.1-flash"])
        XCTAssertEqual(
            MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "x-opencode-session"),
            "session-123"
        )
        XCTAssertEqual(
            MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer sk-test"
        )
    }

    func testOpenCodeTemplatesUseChatCompletionsFilterFlag() {
        for id in ["opencode", "opencode-go"] {
            let template = ProviderTemplate.template(for: id)
            XCTAssertNotNil(template, "\(id) template is missing")
            XCTAssertEqual(template?.apiFormat, .openAI)
            XCTAssertTrue(template?.baseURL.contains("opencode.ai") == true)
            XCTAssertTrue(template?.requiresChatCompletionsModelFilter == true)
            XCTAssertTrue(template?.injectsOpenCodeSession == true)
            XCTAssertEqual(template?.defaultHeaders["x-opencode-client"], "openchat")
        }
    }

    func testFetchOpenCodeProviderInjectsCatalogSessionHeader() async throws {
        MockURLProtocol.enqueue(json: #"{"data":[{"id":"deepseek-v4.1-flash","api":{"chat-completions":{}}}]}"#)

        let provider = ConfiguredProvider(
            id: "opencode-go",
            templateID: "opencode-go",
            name: "OpenCode Go",
            symbolName: "chevron.left.forwardslash.chevron.right",
            tint: "#2563EB",
            baseURL: "https://example.com/v1",
            apiFormat: .openAI,
            models: [],
            requiresAPIKey: true,
            isEnabled: true
        )

        _ = try await ProviderModelsClient(session: makeSession()).fetchModels(for: provider, apiKey: "sk-test")
        XCTAssertEqual(
            MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "x-opencode-session"),
            "openchat-catalog-opencode-go"
        )
    }

    func testDecodeOpenAIModelsIgnoresMalformedAPIField() throws {
        let json = Data("""
        {
          "data": [
            { "id": "model-a", "api": "not-an-object" },
            { "id": "model-b" }
          ]
        }
        """.utf8)

        let models = try ProviderModelsClient.decodeOpenAIModels(from: json)
        XCTAssertEqual(models.map(\.id), ["model-a", "model-b"])
    }
}

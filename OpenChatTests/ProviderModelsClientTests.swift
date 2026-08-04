import XCTest
@testable import OpenChat

final class ProviderModelsClientTests: XCTestCase {
    func testDecodeOpenAIModelsFiltersNonChat() throws {
        let json = """
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
        """.data(using: .utf8)!

        let models = try ProviderModelsClient.decodeOpenAIModels(from: json)
        XCTAssertEqual(models.map(\.id), ["gpt-4o", "o4-mini", "deepseek-chat"])
        XCTAssertEqual(models[0].capabilities, [.vision, .tools])
        XCTAssertEqual(models[1].capabilities, [.vision, .tools, .reasoning])
        XCTAssertEqual(models[2].capabilities, [.tools])
    }

    func testDecodeOpenAIModelsUsesArchitectureMetadataWhenPresent() throws {
        let json = """
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
        """.data(using: .utf8)!

        let models = try ProviderModelsClient.decodeOpenAIModels(from: json)
        XCTAssertEqual(models[0].capabilities, [])
        XCTAssertEqual(models[1].capabilities, [.vision, .tools])
    }

    func testDecodeAnthropicModelsMapsCapabilities() throws {
        let json = """
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
        """.data(using: .utf8)!

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
        let json = """
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
        """.data(using: .utf8)!

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
}

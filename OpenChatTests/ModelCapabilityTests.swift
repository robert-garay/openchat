import XCTest
@testable import OpenChat

final class ModelCapabilityTests: XCTestCase {
    func testInferenceFromModalitiesAndParameters() {
        let caps = ModelCapability.inferred(
            inputModalities: ["text", "image", "file", "audio"],
            outputModalities: ["text", "image", "audio"],
            supportedParameters: ["tools", "temperature", "reasoning"],
            modelID: "openai/gpt-test",
            modelName: "GPT Test"
        )
        XCTAssertEqual(caps, [
            .vision, .imageGen, .files, .audioIn, .audioOut, .tools, .reasoning
        ])
    }

    func testSearchInferenceFromModelID() {
        let caps = ModelCapability.inferred(
            inputModalities: ["text"],
            outputModalities: ["text"],
            modelID: "perplexity/sonar-pro",
            modelName: "Sonar Pro"
        )
        XCTAssertEqual(caps, [.search])
    }

    func testReasoningInferenceFromModelID() {
        let caps = ModelCapability.inferred(
            inputModalities: ["text"],
            outputModalities: ["text"],
            modelID: "deepseek/deepseek-reasoner",
            modelName: "DeepSeek R1"
        )
        XCTAssertEqual(caps, [.reasoning])
    }

    func testAIModelLegacySupportsVisionDecoding() throws {
        let json = """
        {"id":"x","displayName":"X","supportsVision":true}
        """.data(using: .utf8)!
        let model = try JSONDecoder().decode(AIModel.self, from: json)
        XCTAssertTrue(model.supportsVision)
        XCTAssertEqual(model.capabilities, [.vision])
    }

    func testAIModelCapabilitiesRoundTrip() throws {
        let model = AIModel(
            id: "gpt",
            displayName: "GPT",
            capabilities: [.tools, .vision, .reasoning]
        )
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(AIModel.self, from: data)
        XCTAssertEqual(decoded.capabilities, [.vision, .tools, .reasoning])
        XCTAssertTrue(decoded.supportsVision)
    }

    func testOpenRouterCatalogMapsCapabilities() {
        let model = OpenRouterCatalogModel(
            id: "meta-llama/llama-4-maverick",
            name: "Meta: Llama 4 Maverick",
            promptPrice: 0.1,
            completionPrice: 0.2,
            inputModalities: ["text", "image"],
            outputModalities: ["text"],
            supportedParameters: ["tools"],
            isAlias: false
        )
        XCTAssertEqual(model.capabilities, [.vision, .tools])
        XCTAssertTrue(model.asAIModel.supportsVision)
        XCTAssertEqual(model.asAIModel.capabilities, [.vision, .tools])
    }

    func testAIModelSupportsTools() {
        let withTools = AIModel(id: "a", displayName: "A", capabilities: [.tools])
        let withoutTools = AIModel(id: "b", displayName: "B", capabilities: [.vision])
        XCTAssertTrue(withTools.supportsTools)
        XCTAssertFalse(withoutTools.supportsTools)
    }

    func testMatchesRequiresAllSelectedCapabilities() {
        let caps: [ModelCapability] = [.vision, .tools, .reasoning]
        XCTAssertTrue(ModelCapability.matches(caps, filters: []))
        XCTAssertTrue(ModelCapability.matches(caps, filters: [.vision]))
        XCTAssertTrue(ModelCapability.matches(caps, filters: [.vision, .tools]))
        XCTAssertFalse(ModelCapability.matches(caps, filters: [.vision, .search]))
        XCTAssertFalse(ModelCapability.matches([.vision], filters: [.vision, .tools]))
    }
}

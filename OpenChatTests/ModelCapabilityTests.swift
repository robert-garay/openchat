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
        // Params omitted → tools inferred for the deepseek-reasoner family too.
        XCTAssertEqual(caps, [.tools, .reasoning])
    }

    func testIdentityHeuristicsWhenModalitiesUnknown() {
        let gpt4o = ModelCapability.inferred(
            inputModalities: [],
            outputModalities: [],
            modelID: "gpt-4o",
            modelName: "gpt-4o"
        )
        XCTAssertEqual(gpt4o, [.vision, .tools])

        let gemini = ModelCapability.inferred(
            inputModalities: [],
            outputModalities: [],
            modelID: "gemini-2.5-pro",
            modelName: "gemini-2.5-pro"
        )
        XCTAssertEqual(gemini, [.vision, .tools])

        let deepseekChat = ModelCapability.inferred(
            inputModalities: [],
            outputModalities: [],
            modelID: "deepseek-chat",
            modelName: "deepseek-chat"
        )
        XCTAssertEqual(deepseekChat, [.tools])
    }

    func testDoesNotOverrideExplicitTextOnlyModalitiesWithVisionHeuristic() {
        let caps = ModelCapability.inferred(
            inputModalities: ["text"],
            outputModalities: ["text"],
            supportedParameters: ["temperature"],
            modelID: "gpt-4o",
            modelName: "gpt-4o"
        )
        // Provider explicitly reported text-only + no tools param → trust metadata.
        XCTAssertEqual(caps, [])
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

    func testEffortInferenceFromParameters() {
        let caps = ModelCapability.inferred(
            inputModalities: ["text"],
            outputModalities: ["text"],
            supportedParameters: ["reasoning_effort", "tools"],
            modelID: "openai/o3-mini",
            modelName: "o3-mini"
        )
        XCTAssertEqual(caps, [.tools, .reasoning, .effort])
    }

    func testEffortInferenceFromModelID() {
        let caps = ModelCapability.inferred(
            inputModalities: [],
            outputModalities: [],
            modelID: "o3-mini",
            modelName: "o3-mini"
        )
        XCTAssertTrue(caps.contains(.effort))
        XCTAssertTrue(caps.contains(.reasoning))
    }

    func testEffortInferenceForGPT56Sol() {
        let caps = ModelCapability.inferred(
            inputModalities: [],
            outputModalities: [],
            modelID: "openai/gpt-5.6-sol",
            modelName: "gpt-5.6-sol"
        )
        XCTAssertTrue(caps.contains(.reasoning))
        XCTAssertTrue(caps.contains(.effort))
    }

    func testEffortNotInferredForDeepSeekR1() {
        let caps = ModelCapability.inferred(
            inputModalities: [],
            outputModalities: [],
            modelID: "deepseek/deepseek-reasoner",
            modelName: "DeepSeek R1"
        )
        XCTAssertTrue(caps.contains(.reasoning))
        XCTAssertFalse(caps.contains(.effort))
    }

    func testAIModelSupportsEffort() {
        let withEffort = AIModel(id: "o3-mini", displayName: "O3 Mini", capabilities: [.effort])
        let withoutEffort = AIModel(id: "gpt-4o", displayName: "GPT-4o", capabilities: [.tools])
        XCTAssertTrue(withEffort.supportsEffort)
        XCTAssertFalse(withoutEffort.supportsEffort)
    }

    func testAIModelSupportsImageGenAndModalities() {
        let imageModel = AIModel(
            id: "google/gemini-2.5-flash-image",
            displayName: "Flash Image",
            capabilities: [.vision, .imageGen]
        )
        XCTAssertTrue(imageModel.supportsImageGen)
        XCTAssertEqual(imageModel.chatOutputModalities, ["image", "text"])

        let textOnly = AIModel(id: "x", displayName: "X", capabilities: [.tools])
        XCTAssertFalse(textOnly.supportsImageGen)
        XCTAssertNil(textOnly.chatOutputModalities)
    }

    func testImageGenHeuristicFromModelID() {
        let caps = ModelCapability.inferred(
            inputModalities: [],
            outputModalities: [],
            modelID: "google/gemini-2.5-flash-image",
            modelName: "Gemini 2.5 Flash Image"
        )
        XCTAssertTrue(caps.contains(.imageGen))
        XCTAssertTrue(caps.contains(.vision))
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

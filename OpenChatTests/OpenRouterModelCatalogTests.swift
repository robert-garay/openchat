import XCTest
@testable import OpenChat

final class OpenRouterModelCatalogTests: XCTestCase {
    private let sampleModels: [OpenRouterCatalogModel] = [
        OpenRouterCatalogModel(
            id: "~deepseek/deepseek-alias",
            name: "DeepSeek Alias",
            created: 3,
            contextLength: 128_000,
            huggingFaceID: "deepseek-ai/DeepSeek",
            promptPrice: 0,
            completionPrice: 0,
            modality: "text->text",
            inputModalities: ["text"],
            outputModalities: ["text"],
            isAlias: true
        ),
        OpenRouterCatalogModel(
            id: "openrouter/free",
            name: "Free Models Router",
            created: 2,
            contextLength: 200_000,
            huggingFaceID: nil,
            promptPrice: 0,
            completionPrice: 0,
            modality: "text->text",
            inputModalities: ["text"],
            outputModalities: ["text"],
            isAlias: false
        ),
        OpenRouterCatalogModel(
            id: "google/gemma-4-31b-it:free",
            name: "Google: Gemma 4 31B (free)",
            created: 10,
            contextLength: 262_144,
            huggingFaceID: "google/gemma-4-31B-it",
            promptPrice: 0,
            completionPrice: 0,
            modality: "text->text",
            inputModalities: ["text"],
            outputModalities: ["text"],
            isAlias: false
        ),
        OpenRouterCatalogModel(
            id: "nvidia/nemotron-3-ultra-550b-a55b:free",
            name: "NVIDIA: Nemotron 3 Ultra (free)",
            created: 9,
            contextLength: 1_000_000,
            huggingFaceID: "nvidia/Nemotron",
            promptPrice: 0,
            completionPrice: 0,
            modality: "text->text",
            inputModalities: ["text"],
            outputModalities: ["text"],
            isAlias: false
        ),
        OpenRouterCatalogModel(
            id: "poolside/laguna-s-2.1:free",
            name: "Poolside: Laguna S 2.1 (free)",
            created: 11,
            contextLength: 262_144,
            huggingFaceID: "poolside/Laguna-S-2.1",
            promptPrice: 0,
            completionPrice: 0,
            modality: "text->text",
            inputModalities: ["text"],
            outputModalities: ["text"],
            isAlias: false
        ),
        OpenRouterCatalogModel(
            id: "deepseek/deepseek-chat",
            name: "DeepSeek: DeepSeek V3",
            created: 8,
            contextLength: 163_840,
            huggingFaceID: "deepseek-ai/DeepSeek-V3",
            promptPrice: 0.00000014,
            completionPrice: 0.00000028,
            modality: "text->text",
            inputModalities: ["text"],
            outputModalities: ["text"],
            isAlias: false
        ),
        OpenRouterCatalogModel(
            id: "deepseek/deepseek-v4-flash-0731",
            name: "DeepSeek: DeepSeek V4 Flash 0731",
            created: 12,
            contextLength: 1_048_576,
            huggingFaceID: "deepseek-ai/DeepSeek-V4-Flash-0731",
            promptPrice: 0.00000009,
            completionPrice: 0.00000018,
            modality: "text->text",
            inputModalities: ["text"],
            outputModalities: ["text"],
            isAlias: false
        ),
        OpenRouterCatalogModel(
            id: "meta-llama/llama-4-maverick",
            name: "Meta: Llama 4 Maverick",
            created: 7,
            contextLength: 1_048_576,
            huggingFaceID: "meta-llama/Llama-4-Maverick",
            promptPrice: 0.00000015,
            completionPrice: 0.0000006,
            modality: "text->text",
            inputModalities: ["text", "image"],
            outputModalities: ["text"],
            isAlias: false
        ),
        OpenRouterCatalogModel(
            id: "qwen/qwen3-235b-a22b",
            name: "Qwen: Qwen3 235B A22B",
            created: 6,
            contextLength: 131_072,
            huggingFaceID: "Qwen/Qwen3-235B-A22B",
            promptPrice: 0.0000002,
            completionPrice: 0.0000006,
            modality: "text->text",
            inputModalities: ["text"],
            outputModalities: ["text"],
            isAlias: false
        ),
        OpenRouterCatalogModel(
            id: "anthropic/claude-sonnet-4.6",
            name: "Anthropic: Claude Sonnet 4.6",
            created: 5,
            contextLength: 200_000,
            huggingFaceID: nil,
            promptPrice: 0.000003,
            completionPrice: 0.000015,
            modality: "text->text",
            inputModalities: ["text", "image"],
            outputModalities: ["text"],
            isAlias: false
        ),
        OpenRouterCatalogModel(
            id: "google/lyria-3-pro-preview",
            name: "Google: Lyria 3 Pro Preview",
            created: 4,
            contextLength: 0,
            huggingFaceID: nil,
            promptPrice: 0,
            completionPrice: 0,
            modality: "text->audio",
            inputModalities: ["text"],
            outputModalities: ["audio"],
            isAlias: false
        ),
    ]

    func testTopFreeExcludesAliasesRoutersAndNonText() {
        let top = OpenRouterModelCatalog.topFree(from: sampleModels)
        XCTAssertEqual(top.map(\.id), [
            "nvidia/nemotron-3-ultra-550b-a55b:free",
            "google/gemma-4-31b-it:free",
            "poolside/laguna-s-2.1:free",
        ])
        XCTAssertFalse(top.contains { $0.id == "openrouter/free" })
        XCTAssertFalse(top.contains { $0.id.hasPrefix("~") })
        XCTAssertFalse(top.contains { $0.id.contains("lyria") })
    }

    func testTopOpenSourceIsDiverseAcrossOrganizations() {
        let top = OpenRouterModelCatalog.topOpenSource(from: sampleModels)
        XCTAssertEqual(top.map(\.id), [
            "deepseek/deepseek-chat",
            "meta-llama/llama-4-maverick",
            "qwen/qwen3-235b-a22b",
        ])
        XCTAssertEqual(Set(top.map(\.organization)).count, 3)
        XCTAssertFalse(top.contains { $0.isFree })
        XCTAssertFalse(top.contains { $0.id == "anthropic/claude-sonnet-4.6" })
    }

    func testSearchMatchesIDNameAndOrganization() {
        let byOrg = OpenRouterModelCatalog.filtered(models: sampleModels, query: "deepseek")
        XCTAssertTrue(byOrg.contains { $0.id == "deepseek/deepseek-chat" })
        XCTAssertFalse(byOrg.contains { $0.isAlias })

        let byName = OpenRouterModelCatalog.filtered(models: sampleModels, query: "maverick")
        XCTAssertEqual(byName.map(\.id), ["meta-llama/llama-4-maverick"])
    }

    func testFilterByCapabilities() {
        let withTools = OpenRouterCatalogModel(
            id: "meta-llama/llama-vision-tools",
            name: "Meta: Llama Vision Tools",
            created: 20,
            contextLength: 128_000,
            huggingFaceID: "meta-llama/Llama-Vision-Tools",
            promptPrice: 0.0000001,
            completionPrice: 0.0000002,
            modality: "text+image->text",
            inputModalities: ["text", "image"],
            outputModalities: ["text"],
            supportedParameters: ["tools"],
            isAlias: false
        )
        let models = sampleModels + [withTools]

        let visionOnly = OpenRouterModelCatalog.filtered(
            models: models,
            query: "",
            capabilities: [.vision]
        )
        XCTAssertTrue(visionOnly.contains { $0.id == "meta-llama/llama-4-maverick" })
        XCTAssertTrue(visionOnly.contains { $0.id == withTools.id })
        XCTAssertFalse(visionOnly.contains { $0.id == "deepseek/deepseek-chat" })
        XCTAssertTrue(visionOnly.allSatisfy { $0.capabilities.contains(.vision) })

        let visionAndTools = OpenRouterModelCatalog.filtered(
            models: models,
            query: "",
            capabilities: [.vision, .tools]
        )
        XCTAssertEqual(visionAndTools.map(\.id), [withTools.id])
    }

    func testFilterCombinesQueryAndCapabilities() {
        let results = OpenRouterModelCatalog.filtered(
            models: sampleModels,
            query: "llama",
            capabilities: [.vision]
        )
        XCTAssertEqual(results.map(\.id), ["meta-llama/llama-4-maverick"])

        let noMatch = OpenRouterModelCatalog.filtered(
            models: sampleModels,
            query: "deepseek",
            capabilities: [.vision]
        )
        XCTAssertTrue(noMatch.isEmpty)
    }

    func testImageOutputModelsAreBrowsableAndFilterable() {
        let imageOnly = OpenRouterCatalogModel(
            id: "black-forest-labs/flux.2-pro",
            name: "Black Forest Labs: Flux 2 Pro",
            created: 20,
            contextLength: 0,
            huggingFaceID: nil,
            promptPrice: 0.01,
            completionPrice: 0,
            modality: "text+image->image",
            inputModalities: ["text", "image"],
            outputModalities: ["image"],
            isAlias: false
        )
        let textAndImage = OpenRouterCatalogModel(
            id: "google/gemini-2.5-flash-image",
            name: "Google: Gemini 2.5 Flash Image",
            created: 21,
            contextLength: 32_768,
            huggingFaceID: nil,
            promptPrice: 0.01,
            completionPrice: 0.02,
            modality: "text+image->text+image",
            inputModalities: ["text", "image"],
            outputModalities: ["text", "image"],
            isAlias: false
        )

        let models = sampleModels + [imageOnly, textAndImage]
        let searchable = OpenRouterModelCatalog.searchableModels(from: models)
        XCTAssertTrue(searchable.contains { $0.id == imageOnly.id })
        XCTAssertTrue(searchable.contains { $0.id == textAndImage.id })

        let imageGen = OpenRouterModelCatalog.filtered(
            models: models,
            query: "",
            capabilities: [.imageGen]
        )
        XCTAssertTrue(imageGen.contains { $0.id == imageOnly.id })
        XCTAssertTrue(imageGen.contains { $0.id == textAndImage.id })
        XCTAssertEqual(imageOnly.capabilities, [.vision, .imageGen])
        XCTAssertEqual(textAndImage.capabilities, [.vision, .imageGen])
    }

    func testDisplayNameAndSubtitleFormatting() {
        let free = sampleModels.first { $0.id == "google/gemma-4-31b-it:free" }!
        XCTAssertEqual(free.displayName, "Gemma 4 31B")
        XCTAssertEqual(free.subtitle, "Open source · 262K context")

        let oss = sampleModels.first { $0.id == "meta-llama/llama-4-maverick" }!
        XCTAssertEqual(oss.displayName, "Llama 4 Maverick")
        XCTAssertEqual(oss.subtitle, "Open source · 1M context")
        XCTAssertTrue(oss.asAIModel.supportsVision)
    }

    func testOpenRouterModelsClientDecodesCatalogPayload() throws {
        let json = """
        {
          "data": [
            {
              "id": "google/gemma-4-31b-it:free",
              "name": "Google: Gemma 4 31B (free)",
              "created": 10,
              "context_length": 262144,
              "hugging_face_id": "google/gemma-4-31B-it",
              "pricing": { "prompt": "0", "completion": "0" },
                "architecture": {
                "modality": "text->text",
                "input_modalities": ["text"],
                "output_modalities": ["text"]
              },
              "supported_parameters": ["temperature", "tools"]
            },
            {
              "id": "~deepseek/deepseek-alias",
              "name": "Alias",
              "alias_target": { "slug": "deepseek/deepseek-chat" },
              "pricing": { "prompt": "0", "completion": "0" },
              "architecture": {
                "modality": "text->text",
                "input_modalities": ["text"],
                "output_modalities": ["text"]
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let models = try OpenRouterModelsClient.decodeModels(from: json)
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models[0].id, "google/gemma-4-31b-it:free")
        XCTAssertEqual(models[0].supportedParameters, ["temperature", "tools"])
        XCTAssertEqual(models[0].capabilities, [.tools])
        XCTAssertTrue(models[0].isFree)
        XCTAssertTrue(models[0].isOpenSource)
        XCTAssertTrue(models[1].isAlias)
    }

    @MainActor
    func testRememberOpenRouterModelPersistsSelection() {
        let defaults = UserDefaults(suiteName: "com.openchat.tests.openrouter.\(UUID().uuidString)")!
        let store = ProviderStore(defaults: defaults)
        store.addFromTemplate(ProviderTemplate.template(for: "openrouter")!)
        store.setAPIKey("sk-or-test", for: store.provider(withID: "openrouter")!)

        let model = sampleModels.first { $0.id == "meta-llama/llama-4-maverick" }!
        store.rememberOpenRouterModel(model)

        XCTAssertEqual(store.provider(withID: "openrouter")?.models.first?.id, model.id)
        XCTAssertEqual(store.model(providerID: "openrouter", modelID: model.id)?.displayName, "Llama 4 Maverick")
    }
}

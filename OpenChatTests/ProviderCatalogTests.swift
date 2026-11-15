import XCTest
import UIKit
@testable import OpenChat

final class ProviderCatalogTests: XCTestCase {
    func testOpenRouterIsFirstProviderTemplate() {
        XCTAssertEqual(ProviderTemplate.all.first?.id, "openrouter")
    }

    func testOpenCodeTemplatesUseInferenceEndpoints() {
        let zen = ProviderTemplate.template(for: "opencode")
        XCTAssertEqual(zen?.baseURL, "https://opencode.ai/inference/openai/v1")
        XCTAssertEqual(zen?.modelsBaseURL, "https://opencode.ai/inference/v1")

        let go = ProviderTemplate.template(for: "opencode-go")
        XCTAssertEqual(go?.baseURL, "https://opencode.ai/inference/go/openai/v1")
        XCTAssertEqual(go?.modelsBaseURL, "https://opencode.ai/inference/go/v1")
        XCTAssertFalse(go?.usageNote?.isEmpty ?? true, "Go should explain its coding-agent terms")
    }

    func testTemplatesWithoutSplitCatalogFallBackToChatBaseURL() {
        XCTAssertNil(ProviderTemplate.template(for: "openrouter")?.modelsBaseURL)
        XCTAssertNil(ProviderTemplate.template(for: "deepseek")?.modelsBaseURL)
    }

    func testAllTemplatesHaveUniqueIDs() {
        let ids = ProviderTemplate.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testChineseOpenModelProvidersArePresent() {
        let ids = Set(ProviderTemplate.all.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["deepseek", "qwen", "moonshot", "zhipu"]))
    }

    func testTemplateLookupByIDSucceeds() {
        XCTAssertEqual(ProviderTemplate.template(for: "deepseek")?.name, "DeepSeek")
        XCTAssertNil(ProviderTemplate.template(for: "does-not-exist"))
    }

    func testProviderNamesUseCompanyBrandsNotModels() {
        let names = Dictionary(uniqueKeysWithValues: ProviderTemplate.all.map { ($0.id, $0.name) })
        XCTAssertEqual(names["moonshot"], "Moonshot AI")
        XCTAssertEqual(names["qwen"], "Alibaba Cloud")
        XCTAssertEqual(names["zhipu"], "Z.ai")
        XCTAssertEqual(names["yi"], "01.AI")
        XCTAssertEqual(names["google"], "Google")
        XCTAssertEqual(names["mistral"], "Mistral AI")
    }

    func testEveryTemplateHasAnOfficialLogoAsset() {
        for template in ProviderTemplate.all {
            XCTAssertNotNil(template.logoAssetName, "\(template.name) is missing a logo asset mapping")
            XCTAssertEqual(template.logoAssetName, ProviderLogo.assetName(for: template.id))
        }
    }

    func testConfiguredProviderDecodesWithoutCustomHeaders() throws {
        let json = Data("""
        {
          "id": "deepseek",
          "templateID": "deepseek",
          "name": "DeepSeek",
          "symbolName": "sparkles",
          "tint": "#4D6BFE",
          "baseURL": "https://api.deepseek.com/v1",
          "apiFormat": "openAI",
          "models": [],
          "requiresAPIKey": true,
          "isEnabled": true
        }
        """.utf8)

        let provider = try JSONDecoder().decode(ConfiguredProvider.self, from: json)
        XCTAssertTrue(provider.customHeaders.isEmpty)
    }

    func testProviderLogosMapToCompanyAssets() {
        XCTAssertEqual(ProviderLogo.assetName(for: "qwen"), "ProviderLogoAlibabaCloud")
        XCTAssertEqual(ProviderLogo.assetName(for: "moonshot"), "ProviderLogoMoonshot")
        XCTAssertEqual(ProviderLogo.assetName(for: "google"), "ProviderLogoGoogle")
        XCTAssertEqual(ProviderLogo.assetName(for: "deepseek"), "ProviderLogoDeepSeek")
        XCTAssertEqual(ProviderLogo.assetName(for: "openai"), "ProviderLogoOpenAI")
        XCTAssertEqual(ProviderLogo.assetName(for: "anthropic"), "ProviderLogoAnthropic")
    }
}

final class CustomEndpointLogoOptionTests: XCTestCase {
    func testAllOptionsHaveUniqueIDs() {
        let ids = CustomEndpointLogoOption.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testAllOptionsHaveAnAssetInTheCatalog() {
        for option in CustomEndpointLogoOption.all {
            XCTAssertNotNil(UIImage(named: option.logoAssetName), "\(option.name) is missing its logo asset")
        }
    }

    func testOptionLookupByIDSucceeds() {
        XCTAssertEqual(CustomEndpointLogoOption.option(for: "runpod")?.name, "RunPod")
        XCTAssertNil(CustomEndpointLogoOption.option(for: "does-not-exist"))
        XCTAssertNil(CustomEndpointLogoOption.option(for: nil))
    }
}

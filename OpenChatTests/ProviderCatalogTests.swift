import XCTest
@testable import OpenChat

final class ProviderCatalogTests: XCTestCase {
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

    func testProviderLogosMapToCompanyAssets() {
        XCTAssertEqual(ProviderLogo.assetName(for: "qwen"), "ProviderLogoAlibabaCloud")
        XCTAssertEqual(ProviderLogo.assetName(for: "moonshot"), "ProviderLogoMoonshot")
        XCTAssertEqual(ProviderLogo.assetName(for: "google"), "ProviderLogoGoogle")
        XCTAssertEqual(ProviderLogo.assetName(for: "deepseek"), "ProviderLogoDeepSeek")
        XCTAssertEqual(ProviderLogo.assetName(for: "openai"), "ProviderLogoOpenAI")
        XCTAssertEqual(ProviderLogo.assetName(for: "anthropic"), "ProviderLogoAnthropic")
    }
}

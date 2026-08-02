import XCTest
@testable import OpenChat

final class ProviderCatalogTests: XCTestCase {
    func testAllTemplatesHaveUniqueIDs() {
        let ids = ProviderTemplate.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testAllTemplatesHaveAtLeastOneModel() {
        for template in ProviderTemplate.all {
            XCTAssertFalse(template.defaultModels.isEmpty, "\(template.name) has no default models")
        }
    }

    func testChineseOpenModelProvidersArePresent() {
        let ids = Set(ProviderTemplate.all.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["deepseek", "qwen", "moonshot", "zhipu"]))
    }

    func testTemplateLookupByIDSucceeds() {
        XCTAssertEqual(ProviderTemplate.template(for: "deepseek")?.name, "DeepSeek")
        XCTAssertNil(ProviderTemplate.template(for: "does-not-exist"))
    }
}

import XCTest
@testable import OpenChat

final class ManagedFreeTierTests: XCTestCase {
    func testModelUsesRealQwenNameAndOpenRouterID() {
        XCTAssertEqual(ManagedFreeTier.openRouterModelID, "qwen/qwen3.7-flash")
        XCTAssertEqual(ManagedFreeTier.model.displayName, "Qwen3.7 Flash")
        XCTAssertTrue(ManagedFreeTier.model.supportsVision)
        XCTAssertEqual(ManagedFreeTier.makeProvider().models, [ManagedFreeTier.model])
        XCTAssertTrue(ManagedFreeTier.makeProvider().isManagedFreeTier)
    }

    func testQwenLogoResolvesForIncludedProvider() {
        XCTAssertEqual(ProviderLogo.assetName(for: ManagedFreeTier.providerID), "ProviderLogoQwen")
    }
}

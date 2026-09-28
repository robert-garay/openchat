import XCTest
@testable import OpenChat

final class LocalModelRecommendationTests: XCTestCase {
    func testDeviceTierFromPhysicalMemory() {
        XCTAssertEqual(DeviceTier.from(physicalMemoryBytes: 4_000_000_000), .legacy4GB)
        XCTAssertEqual(DeviceTier.from(physicalMemoryBytes: 6_000_000_000), .standard6GB)
        XCTAssertEqual(DeviceTier.from(physicalMemoryBytes: 8_000_000_000), .performance8GB)
        XCTAssertEqual(DeviceTier.from(physicalMemoryBytes: 12_000_000_000), .high12GB)
    }

    func testStandard6EverydayPrefersQwen15B() {
        let models = LocalModelRecommendationEngine.recommendedModels(
            deviceTier: .standard6GB,
            preference: .everydayChat
        )
        XCTAssertEqual(models.first?.mlxModelID, "mlx-community/Qwen2.5-1.5B-Instruct-4bit")
    }

    func testStandard6BestDoesNotSuggest3B() {
        let models = LocalModelRecommendationEngine.recommendedModels(
            deviceTier: .standard6GB,
            preference: .bestOnDevice
        )
        XCTAssertFalse(models.contains { $0.mlxModelID.contains("3B") })
    }

    func testPerformance8BestIncludes3BAnd4B() {
        let models = LocalModelRecommendationEngine.recommendedModels(
            deviceTier: .performance8GB,
            preference: .bestOnDevice
        )
        let ids = Set(models.map(\.mlxModelID))
        XCTAssertTrue(ids.contains("mlx-community/Qwen2.5-3B-Instruct-4bit"))
        XCTAssertTrue(ids.contains("mlx-community/Qwen3-4B-Instruct-2507-4bit"))
    }

    func testLegacy4BestCapsAt06B() {
        let primary = LocalModelRecommendationEngine.primaryModelID(
            physicalMemoryBytes: 4_294_967_296,
            preference: .bestOnDevice
        )
        XCTAssertEqual(primary, "mlx-community/Qwen3-0.6B-4bit")
    }
}

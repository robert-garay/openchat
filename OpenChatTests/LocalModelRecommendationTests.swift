import XCTest
@testable import OpenChat

final class LocalModelRecommendationTests: XCTestCase {
    func testDeviceTierFromPhysicalMemory() {
        let gib = 1_073_741_824
        XCTAssertEqual(DeviceTier.from(physicalMemoryBytes: UInt64(4 * gib)), .legacy4GB)
        XCTAssertEqual(DeviceTier.from(physicalMemoryBytes: UInt64(6 * gib)), .standard6GB)
        XCTAssertEqual(DeviceTier.from(physicalMemoryBytes: UInt64(8 * gib)), .performance8GB)
        XCTAssertEqual(DeviceTier.from(physicalMemoryBytes: UInt64(12 * gib)), .high12GB)
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

    func testPerformance8BestIncludesPinned3BModels() {
        let models = LocalModelRecommendationEngine.recommendedModels(
            deviceTier: .performance8GB,
            preference: .bestOnDevice
        )
        let ids = Set(models.map(\.mlxModelID))
        XCTAssertTrue(ids.contains("mlx-community/Qwen2.5-3B-Instruct-4bit"))
        XCTAssertTrue(ids.contains("mlx-community/Llama-3.2-3B-Instruct-4bit"))
        XCTAssertFalse(ids.contains("mlx-community/Qwen3-4B-Instruct-2507-4bit"))
    }

    func testEveryCatalogIDIsDownloadableInBundledManifest() throws {
        let manifest = try LocalModelsManifestLoader.loadBundled()
        let downloadable = Set(manifest.models.filter(\.isDownloadable).map(\.mlxModelID))
        for modelID in LocalModelRecommendationEngine.allCatalogModelIDs() {
            XCTAssertTrue(
                downloadable.contains(modelID),
                "Catalog references \(modelID) but it is not a downloadable bundled manifest entry"
            )
        }
    }

    func testLegacy4BestCapsAt06B() {
        let primary = LocalModelRecommendationEngine.primaryModelID(
            physicalMemoryBytes: 4_294_967_296,
            preference: .bestOnDevice
        )
        XCTAssertEqual(primary, "mlx-community/Qwen3-0.6B-4bit")
    }

    func testBundledManifestRecommendationsAreDownloadable() throws {
        let manifest = try LocalModelsManifestLoader.loadBundled()
        let context = DeviceContext(
            physicalMemoryBytes: 8 * 1_073_741_824,
            availableImportantDiskBytes: 20_000_000_000,
            machineIdentifier: "iPhone16,1",
            chipPerformanceClass: .premium,
            intelligencePreference: .everydayChat,
            isOnWiFi: true,
            wifiOnlyDownloads: true,
            thermalState: .nominal,
            isLowPowerModeEnabled: false
        )
        let result = LocalModelRecommendationEngine.recommend(manifest: manifest, context: context)
        XCTAssertFalse(result.picks.isEmpty)
        for pick in result.picks {
            XCTAssertTrue(pick.entry.isDownloadable)
            XCTAssertTrue(manifest.models.contains(where: { $0.id == pick.entry.id }))
        }
    }
}

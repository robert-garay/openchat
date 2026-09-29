import XCTest
@testable import OpenChat

final class DeviceAwareRecommendationTests: XCTestCase {
    private let gib: UInt64 = 1_073_741_824

    private func sampleManifest() -> LocalModelsManifest {
        LocalModelsManifest(
            version: 1,
            minAppVersion: "1.2.0",
            models: [
                LocalModelManifestEntry(
                    id: "mlx-community/Qwen3-0.6B-4bit",
                    mlxModelID: "mlx-community/Qwen3-0.6B-4bit",
                    displayName: "Qwen3 0.6B",
                    tier: "legacy4",
                    intelligenceLevel: "quick",
                    minRAMGB: 4,
                    recommendedDevices: [],
                    bytes: 400_000_000,
                    sha256: "a",
                    backend: "mlx",
                    chatTemplate: "qwen",
                    files: [LocalModelManifestFile(path: "m", url: "https://huggingface.co/x", sha256: "b")]
                ),
                LocalModelManifestEntry(
                    id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
                    mlxModelID: "mlx-community/Llama-3.2-1B-Instruct-4bit",
                    displayName: "Llama 3.2 1B",
                    tier: "standard6",
                    intelligenceLevel: "quick",
                    minRAMGB: 6,
                    recommendedDevices: [],
                    bytes: 700_000_000,
                    sha256: "c",
                    backend: "mlx",
                    chatTemplate: "llama3",
                    files: [LocalModelManifestFile(path: "m", url: "https://huggingface.co/y", sha256: "d")]
                ),
                LocalModelManifestEntry(
                    id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                    mlxModelID: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                    displayName: "Qwen2.5 1.5B",
                    tier: "standard6",
                    intelligenceLevel: "everyday",
                    minRAMGB: 6,
                    recommendedDevices: [],
                    bytes: 900_000_000,
                    sha256: "e",
                    backend: "mlx",
                    chatTemplate: "qwen",
                    files: [LocalModelManifestFile(path: "m", url: "https://huggingface.co/z", sha256: "f")]
                )
            ]
        )
    }

    private func context(
        ramGB: Int,
        preference: IntelligencePreference,
        diskBytes: Int64? = 10_000_000_000,
        machine: String = "iPhone15,2",
        wifiOnly: Bool = true,
        onWiFi: Bool = true
    ) -> DeviceContext {
        DeviceContext(
            physicalMemoryBytes: UInt64(ramGB) * gib,
            availableImportantDiskBytes: diskBytes,
            machineIdentifier: machine,
            chipPerformanceClass: ChipPerformanceClass.from(machineIdentifier: machine),
            intelligencePreference: preference,
            isOnWiFi: onWiFi,
            wifiOnlyDownloads: wifiOnly,
            thermalState: .nominal,
            isLowPowerModeEnabled: false
        )
    }

    func testChipClassFromMachine() {
        XCTAssertEqual(ChipPerformanceClass.from(machineIdentifier: "iPhone12,1"), .standard)
        XCTAssertEqual(ChipPerformanceClass.from(machineIdentifier: "iPhone14,2"), .enhanced)
        XCTAssertEqual(ChipPerformanceClass.from(machineIdentifier: "iPhone16,1"), .premium)
    }

    func testStandard6EverydayRanksQwen15BFirst() {
        let result = LocalModelRecommendationEngine.recommend(
            manifest: sampleManifest(),
            context: context(ramGB: 6, preference: .everydayChat)
        )
        XCTAssertEqual(result.primary?.mlxModelID, "mlx-community/Qwen2.5-1.5B-Instruct-4bit")
        XCTAssertEqual(result.primary?.pickLabel, .balanced)
    }

    func testOnlyDownloadableManifestEntriesRecommended() {
        var manifest = sampleManifest()
        manifest.models.append(
            LocalModelManifestEntry(
                id: "stub",
                mlxModelID: "mlx-community/missing",
                displayName: "Stub",
                tier: "standard6",
                intelligenceLevel: "quick",
                minRAMGB: 4,
                recommendedDevices: [],
                bytes: 100,
                sha256: "x",
                backend: "mlx",
                chatTemplate: "qwen",
                files: [],
                notRecommendedReason: "Coming soon"
            )
        )
        let ids = LocalModelRecommendationEngine.recommend(
            manifest: manifest,
            context: context(ramGB: 8, preference: .quickReplies)
        ).picks.map(\.mlxModelID)
        XCTAssertFalse(ids.contains("mlx-community/missing"))
    }

    func testInsufficientStorageBlocksPrimary() {
        let result = LocalModelRecommendationEngine.recommend(
            manifest: sampleManifest(),
            context: context(ramGB: 6, preference: .everydayChat, diskBytes: 100_000_000)
        )
        XCTAssertTrue(result.primary?.isBlockedForDownload == true)
        XCTAssertTrue(result.reasons.contains { $0.kind == .storage })
    }

    func testWifiWarningInReasons() {
        let result = LocalModelRecommendationEngine.recommend(
            manifest: sampleManifest(),
            context: context(ramGB: 6, preference: .everydayChat, wifiOnly: true, onWiFi: false)
        )
        XCTAssertTrue(result.reasons.contains { $0.kind == .warning && $0.message.contains("Wi") })
    }

    func testGracefulWhenCatalogIDMissingFromManifest() {
        let manifest = LocalModelsManifest(
            version: 1,
            minAppVersion: nil,
            models: sampleManifest().models.filter { $0.mlxModelID.contains("Llama") }
        )
        let result = LocalModelRecommendationEngine.recommend(
            manifest: manifest,
            context: context(ramGB: 6, preference: .everydayChat)
        )
        XCTAssertEqual(result.picks.count, 1)
        XCTAssertEqual(result.primary?.mlxModelID, "mlx-community/Llama-3.2-1B-Instruct-4bit")
    }
}

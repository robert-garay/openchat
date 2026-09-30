import XCTest
@testable import OpenChat

final class LocalModelVendorTests: XCTestCase {
    func testVendorDetectionFromMLXModelID() {
        let llama = makeEntry(id: "mlx-community/Llama-3.2-1B-Instruct-4bit", level: "quick")
        XCTAssertEqual(LocalModelVendor.from(entry: llama), .meta)

        let qwen = makeEntry(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", level: "everyday")
        XCTAssertEqual(LocalModelVendor.from(entry: qwen), .qwen)

        let phi = makeEntry(id: "mlx-community/Phi-3.5-mini-instruct-4bit", level: "best")
        XCTAssertEqual(LocalModelVendor.from(entry: phi), .microsoft)
    }

    func testPerformanceTierLabelMapping() {
        XCTAssertEqual(makeEntry(id: "a", level: "quick").performanceTierLabel, .fast)
        XCTAssertEqual(makeEntry(id: "b", level: "everyday").performanceTierLabel, .balanced)
        XCTAssertEqual(makeEntry(id: "c", level: "best").performanceTierLabel, .strongest)
    }

    func testLogoAssetNamesMatchProviderCatalogConvention() {
        XCTAssertEqual(LocalModelVendor.meta.logoAssetName, "ProviderLogoMeta")
        XCTAssertEqual(LocalModelVendor.qwen.logoAssetName, "ProviderLogoAlibabaCloud")
        XCTAssertEqual(LocalModelVendor.microsoft.logoAssetName, "ProviderLogoMicrosoft")
    }

    func testGroupedEntriesPreservesVendorOrder() {
        let entries = [
            makeEntry(id: "mlx-community/Phi-3.5-mini-instruct-4bit", level: "best"),
            makeEntry(id: "mlx-community/Llama-3.2-1B-Instruct-4bit", level: "quick"),
            makeEntry(id: "mlx-community/Qwen2.5-0.5B-Instruct-4bit", level: "quick")
        ]
        let groups = LocalModelVendor.groupedDownloadableEntries(from: entries)
        XCTAssertEqual(groups.map(\.vendor), [.meta, .qwen, .microsoft])
    }

    private func makeEntry(id: String, level: String) -> LocalModelManifestEntry {
        LocalModelManifestEntry(
            id: id,
            mlxModelID: id,
            displayName: id,
            tier: "standard6",
            intelligenceLevel: level,
            minRAMGB: 6,
            recommendedDevices: [],
            bytes: 1000,
            sha256: "abc",
            backend: "mlx",
            chatTemplate: "llama3",
            files: [LocalModelManifestFile(path: "m", url: "https://huggingface.co/x/y/resolve/main/m", sha256: "d", bytes: 1000)],
            defaultForTier: nil,
            notRecommendedReason: nil
        )
    }
}

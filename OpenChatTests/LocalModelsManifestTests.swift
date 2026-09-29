import XCTest
@testable import OpenChat

final class LocalModelsManifestTests: XCTestCase {
    func testBundledManifestParsesAndValidates() throws {
        let manifest = try LocalModelsManifestLoader.loadBundled()
        XCTAssertEqual(manifest.version, 2)
        XCTAssertGreaterThanOrEqual(manifest.models.count, 7)
        let llama = try XCTUnwrap(manifest.models.first { $0.mlxModelID.contains("Llama-3.2-1B") })
        XCTAssertFalse(llama.files.isEmpty)
        XCTAssertTrue(llama.isDownloadable)
        let downloadable = manifest.models.filter(\.isDownloadable)
        XCTAssertFalse(downloadable.isEmpty)
        for entry in downloadable {
            XCTAssertFalse(entry.files.isEmpty, entry.id)
            XCTAssertTrue(entry.mlxModelID.hasPrefix("mlx-community/"))
        }
    }

    func testBundleDigestMatchesManifestForFixture() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let contents: [String: String] = [
            "config.json": "hello",
            "weights.bin": "world"
        ]
        for (name, text) in contents {
            try Data(text.utf8).write(to: temp.appendingPathComponent(name))
        }
        let digest = try LocalModelChecksum.bundleDigest(modelDirectory: temp, relativePaths: Array(contents.keys))
        XCTAssertEqual(digest.count, 64)
        try? FileManager.default.removeItem(at: temp)
    }

    func testInstallStateMachineBlocksDoubleDownload() {
        XCTAssertTrue(LocalModelInstallStateMachine.canStartDownload(from: .notInstalled))
        XCTAssertFalse(LocalModelInstallStateMachine.canStartDownload(from: .downloading))
        XCTAssertFalse(LocalModelInstallStateMachine.canStartDownload(from: .ready))
    }
}

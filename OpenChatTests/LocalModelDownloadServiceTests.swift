import XCTest
@testable import OpenChat

final class RangeDownloadMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastRangeHeader: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        Self.lastRangeHeader = request.value(forHTTPHeaderField: "Range")

        let offset: Int
        let status: Int
        if let range = Self.lastRangeHeader, range.hasPrefix("bytes=") {
            let startText = range.dropFirst(6).split(separator: "-", maxSplits: 1).first ?? ""
            offset = Int(startText) ?? 0
            if offset >= Self.payload.count {
                status = 416
            } else {
                status = 206
            }
        } else {
            offset = 0
            status = 200
        }

        let body: Data
        if status == 416 {
            body = Data()
        } else if status == 206 {
            body = Self.payload.subdata(in: offset ..< Self.payload.count)
        } else {
            body = Self.payload
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/octet-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LocalModelDownloadServiceTests: XCTestCase {
    override func tearDown() {
        RangeDownloadMockURLProtocol.payload = Data()
        RangeDownloadMockURLProtocol.requestCount = 0
        RangeDownloadMockURLProtocol.lastRangeHeader = nil
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RangeDownloadMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testDownloadResumesUsingHTTPRange() async throws {
        let payload = Data("hello-world-bytes".utf8)
        RangeDownloadMockURLProtocol.payload = payload

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let installStore = LocalModelInstallStore(directory: tempRoot)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let staging = tempRoot.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let stagedFile = staging.appendingPathComponent("weights.bin")
        try payload.write(to: stagedFile)
        let fileDigest = try LocalModelChecksum.sha256Hex(of: stagedFile)
        let bundleDigest = try LocalModelChecksum.bundleDigest(modelDirectory: staging, relativePaths: ["weights.bin"])
        let entry = LocalModelManifestEntry(
            id: "test-model",
            mlxModelID: "mlx-community/test",
            displayName: "Test",
            tier: "fast",
            intelligenceLevel: "fast",
            minRAMGB: 1,
            recommendedDevices: [],
            bytes: payload.count,
            sha256: bundleDigest,
            backend: "mlx",
            chatTemplate: "llama",
            files: [
                LocalModelManifestFile(
                    path: "weights.bin",
                    url: "https://example.com/weights.bin",
                    sha256: fileDigest,
                    bytes: payload.count
                )
            ]
        )

        let partial = installStore
            .modelDirectory(for: entry.id)
            .appendingPathComponent("weights.bin.partial")
        try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("hello-".utf8).write(to: partial)

        try await LocalModelDownloadService.download(
            entry: entry,
            manifestVersion: 1,
            installStore: installStore,
            wifiOnly: false,
            urlSession: makeSession()
        ) { _ in }

        XCTAssertEqual(RangeDownloadMockURLProtocol.requestCount, 1)
        XCTAssertEqual(RangeDownloadMockURLProtocol.lastRangeHeader, "bytes=6-")

        let destination = installStore.modelDirectory(for: entry.id).appendingPathComponent("weights.bin")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let onDisk = try Data(contentsOf: destination)
        XCTAssertEqual(onDisk, payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }
}
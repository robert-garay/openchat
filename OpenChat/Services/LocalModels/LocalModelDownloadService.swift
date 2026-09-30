import Foundation
import Network

struct LocalModelDownloadProgress: Sendable {
    var modelID: String
    var fractionCompleted: Double
    var receivedBytes: Int
    var totalBytes: Int
}

enum LocalModelDownloadService {
    static func isOnWiFi() -> Bool {
        final class WiFiResult: @unchecked Sendable {
            var isWiFi = false
        }
        let result = WiFiResult()
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { path in
            result.isWiFi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            semaphore.signal()
        }
        let queue = DispatchQueue(label: "com.openchat.local-models.wifi-check")
        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 2)
        monitor.cancel()
        return result.isWiFi
    }

    static func download(
        entry: LocalModelManifestEntry,
        manifestVersion: Int,
        installStore: LocalModelInstallStore,
        wifiOnly: Bool,
        progress: @escaping @Sendable (LocalModelDownloadProgress) -> Void
    ) async throws {
        guard entry.isDownloadable else {
            throw LocalModelsError.downloadFailed("Model is not available for download.")
        }
        if wifiOnly, !isOnWiFi() {
            throw LocalModelsError.wifiRequired
        }

        let physicalGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        guard physicalGB >= entry.minRAMGB else {
            throw LocalModelsError.insufficientRAM(requiredGB: entry.minRAMGB)
        }

        let modelDir = installStore.modelDirectory(for: entry.id)
        try? FileManager.default.removeItem(at: modelDir)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        let totalBytes = entry.files.reduce(0) { $0 + ($1.bytes ?? 0) }
        var receivedBeforeCurrentFile = 0

        progress(
            LocalModelDownloadProgress(
                modelID: entry.id,
                fractionCompleted: 0,
                receivedBytes: 0,
                totalBytes: totalBytes
            )
        )

        for file in entry.files {
            try Task.checkCancellation()
            guard let remoteURL = URL(string: file.url) else {
                throw LocalModelsError.invalidURL(file.url)
            }
            let destination = modelDir.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let tempURL = try await downloadFile(
                from: remoteURL,
                fileBytesHint: file.bytes,
                modelID: entry.id,
                receivedBeforeCurrentFile: receivedBeforeCurrentFile,
                totalBytes: totalBytes,
                progress: progress
            )
            defer { try? FileManager.default.removeItem(at: tempURL) }

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)

            let digest = try LocalModelChecksum.sha256Hex(of: destination)
            guard digest.lowercased() == file.sha256.lowercased() else {
                try? FileManager.default.removeItem(at: modelDir)
                throw LocalModelsError.checksumMismatch(path: file.path)
            }

            let bytesForFile: Int
            if let knownBytes = file.bytes {
                bytesForFile = knownBytes
            } else {
                bytesForFile = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            }
            receivedBeforeCurrentFile += bytesForFile
            let fraction = totalBytes > 0 ? Double(receivedBeforeCurrentFile) / Double(totalBytes) : 1
            progress(
                LocalModelDownloadProgress(
                    modelID: entry.id,
                    fractionCompleted: min(1, fraction),
                    receivedBytes: receivedBeforeCurrentFile,
                    totalBytes: totalBytes
                )
            )
        }

        let bundleDigest = try LocalModelChecksum.bundleDigest(
            modelDirectory: modelDir,
            relativePaths: entry.files.map(\.path)
        )
        guard bundleDigest.lowercased() == entry.sha256.lowercased() else {
            try? FileManager.default.removeItem(at: modelDir)
            throw LocalModelsError.bundleChecksumMismatch
        }

        var excludedFromBackup = modelDir
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excludedFromBackup.setResourceValues(values)
        _ = manifestVersion
    }

    private static func downloadFile(
        from remoteURL: URL,
        fileBytesHint: Int?,
        modelID: String,
        receivedBeforeCurrentFile: Int,
        totalBytes: Int,
        progress: @escaping @Sendable (LocalModelDownloadProgress) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let handler = DownloadHandler(
                remoteURL: remoteURL,
                fileBytesHint: fileBytesHint,
                modelID: modelID,
                receivedBeforeCurrentFile: receivedBeforeCurrentFile,
                totalBytes: totalBytes,
                progress: progress,
                continuation: continuation
            )
            handler.start()
        }
    }
}

// ponytail: one small delegate box; upgrade path is injectable URLSession for tests.
private final class DownloadHandler: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let remoteURL: URL
    private let fileBytesHint: Int?
    private let modelID: String
    private let receivedBeforeCurrentFile: Int
    private let totalBytes: Int
    private let progress: @Sendable (LocalModelDownloadProgress) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession!
    private var expectedFileBytes: Int64 = 0

    init(
        remoteURL: URL,
        fileBytesHint: Int?,
        modelID: String,
        receivedBeforeCurrentFile: Int,
        totalBytes: Int,
        progress: @escaping @Sendable (LocalModelDownloadProgress) -> Void,
        continuation: CheckedContinuation<URL, Error>
    ) {
        self.remoteURL = remoteURL
        self.fileBytesHint = fileBytesHint
        self.modelID = modelID
        self.receivedBeforeCurrentFile = receivedBeforeCurrentFile
        self.totalBytes = totalBytes
        self.progress = progress
        self.continuation = continuation
        super.init()
        let config = URLSessionConfiguration.ephemeral
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func start() {
        session.downloadTask(with: remoteURL).resume()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            expectedFileBytes = totalBytesExpectedToWrite
        } else if expectedFileBytes == 0, let hint = fileBytesHint {
            expectedFileBytes = Int64(hint)
        }

        let fileReceived = Int(totalBytesWritten)
        let aggregateReceived = receivedBeforeCurrentFile + fileReceived
        let fraction: Double
        if totalBytes > 0 {
            fraction = min(1, Double(aggregateReceived) / Double(totalBytes))
        } else if expectedFileBytes > 0 {
            fraction = min(1, Double(totalBytesWritten) / Double(expectedFileBytes))
        } else {
            fraction = 0
        }

        progress(
            LocalModelDownloadProgress(
                modelID: modelID,
                fractionCompleted: fraction,
                receivedBytes: aggregateReceived,
                totalBytes: totalBytes
            )
        )
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let http = downloadTask.response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? -1
            finish(.failure(LocalModelsError.downloadFailed("HTTP \(code) for \(remoteURL.absoluteString)")))
            return
        }
        let tempCopy = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        do {
            if FileManager.default.fileExists(atPath: tempCopy.path) {
                try FileManager.default.removeItem(at: tempCopy)
            }
            try FileManager.default.copyItem(at: location, to: tempCopy)
            finish(.success(tempCopy))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard continuation != nil else { return }
        session.invalidateAndCancel()
        switch result {
        case .success(let url):
            continuation?.resume(returning: url)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

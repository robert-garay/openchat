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
        urlSession: URLSession = .shared,
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

            if FileManager.default.fileExists(atPath: destination.path) {
                let digest = try LocalModelChecksum.sha256Hex(of: destination)
                if digest.lowercased() == file.sha256.lowercased() {
                    let bytesForFile = try fileByteCount(at: destination, knownBytes: file.bytes)
                    receivedBeforeCurrentFile += bytesForFile
                    reportProgress(
                        modelID: entry.id,
                        receivedBeforeCurrentFile: receivedBeforeCurrentFile,
                        totalBytes: totalBytes,
                        progress: progress
                    )
                    continue
                }
                try? FileManager.default.removeItem(at: destination)
            }

            let partialDestination = partialURL(for: destination)
            try await downloadFileResuming(
                from: remoteURL,
                to: partialDestination,
                fileBytesHint: file.bytes,
                modelID: entry.id,
                receivedBeforeCurrentFile: receivedBeforeCurrentFile,
                totalBytes: totalBytes,
                urlSession: urlSession,
                progress: progress
            )

            let partialDigest = try LocalModelChecksum.sha256Hex(of: partialDestination)
            guard partialDigest.lowercased() == file.sha256.lowercased() else {
                try? FileManager.default.removeItem(at: partialDestination)
                try? FileManager.default.removeItem(at: modelDir)
                throw LocalModelsError.checksumMismatch(path: file.path)
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: partialDestination, to: destination)

            let bytesForFile = try fileByteCount(at: destination, knownBytes: file.bytes)
            receivedBeforeCurrentFile += bytesForFile
            reportProgress(
                modelID: entry.id,
                receivedBeforeCurrentFile: receivedBeforeCurrentFile,
                totalBytes: totalBytes,
                progress: progress
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

    private static func partialURL(for destination: URL) -> URL {
        destination.appendingPathExtension("partial")
    }

    private static func fileByteCount(at url: URL, knownBytes: Int?) throws -> Int {
        if let knownBytes {
            return knownBytes
        }
        return try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    }

    private static func reportProgress(
        modelID: String,
        receivedBeforeCurrentFile: Int,
        totalBytes: Int,
        progress: @escaping @Sendable (LocalModelDownloadProgress) -> Void
    ) {
        let fraction = totalBytes > 0 ? Double(receivedBeforeCurrentFile) / Double(totalBytes) : 1
        progress(
            LocalModelDownloadProgress(
                modelID: modelID,
                fractionCompleted: min(1, fraction),
                receivedBytes: receivedBeforeCurrentFile,
                totalBytes: totalBytes
            )
        )
    }

    private static func downloadFileResuming(
        from remoteURL: URL,
        to partialDestination: URL,
        fileBytesHint: Int?,
        modelID: String,
        receivedBeforeCurrentFile: Int,
        totalBytes: Int,
        urlSession: URLSession,
        progress: @escaping @Sendable (LocalModelDownloadProgress) -> Void
    ) async throws {
        try FileManager.default.createDirectory(
            at: partialDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var resumeFrom = 0
        if FileManager.default.fileExists(atPath: partialDestination.path) {
            resumeFrom = try partialDestination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        }

        var request = URLRequest(url: remoteURL)
        if resumeFrom > 0 {
            request.setValue("bytes=\(resumeFrom)-", forHTTPHeaderField: "Range")
        }

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LocalModelsError.downloadFailed("No HTTP response for \(remoteURL.absoluteString)")
        }

        let fileHandle: FileHandle
        if resumeFrom > 0 {
            if http.statusCode == 200 {
                // Server ignored Range — restart from scratch.
                try? FileManager.default.removeItem(at: partialDestination)
                FileManager.default.createFile(atPath: partialDestination.path, contents: nil)
                fileHandle = try FileHandle(forWritingTo: partialDestination)
                resumeFrom = 0
            } else if http.statusCode == 416 {
                return
            } else if http.statusCode != 206 {
                throw LocalModelsError.downloadFailed("HTTP \(http.statusCode) for \(remoteURL.absoluteString)")
            } else {
                fileHandle = try FileHandle(forWritingTo: partialDestination)
                try fileHandle.seekToEnd()
            }
        } else {
            guard (200 ... 299).contains(http.statusCode) else {
                throw LocalModelsError.downloadFailed("HTTP \(http.statusCode) for \(remoteURL.absoluteString)")
            }
            FileManager.default.createFile(atPath: partialDestination.path, contents: nil)
            fileHandle = try FileHandle(forWritingTo: partialDestination)
        }

        defer { try? fileHandle.close() }

        var expectedFileBytes = Int64(fileBytesHint ?? 0)
        if expectedFileBytes == 0, let contentLength = http.value(forHTTPHeaderField: "Content-Length"),
           let length = Int64(contentLength) {
            expectedFileBytes = length + Int64(resumeFrom)
        }

        var chunk = Data()
        chunk.reserveCapacity(65_536)
        var fileReceived = resumeFrom

        for try await byte in bytes {
            try Task.checkCancellation()
            chunk.append(byte)
            if chunk.count >= 65_536 {
                try fileHandle.write(contentsOf: chunk)
                fileReceived += chunk.count
                chunk.removeAll(keepingCapacity: true)
                emitFileProgress(
                    modelID: modelID,
                    fileReceived: fileReceived,
                    receivedBeforeCurrentFile: receivedBeforeCurrentFile,
                    totalBytes: totalBytes,
                    expectedFileBytes: expectedFileBytes,
                    progress: progress
                )
            }
        }
        if !chunk.isEmpty {
            try fileHandle.write(contentsOf: chunk)
            fileReceived += chunk.count
        }
        emitFileProgress(
            modelID: modelID,
            fileReceived: fileReceived,
            receivedBeforeCurrentFile: receivedBeforeCurrentFile,
            totalBytes: totalBytes,
            expectedFileBytes: expectedFileBytes,
            progress: progress
        )
    }

    private static func emitFileProgress(
        modelID: String,
        fileReceived: Int,
        receivedBeforeCurrentFile: Int,
        totalBytes: Int,
        expectedFileBytes: Int64,
        progress: @escaping @Sendable (LocalModelDownloadProgress) -> Void
    ) {
        let aggregateReceived = receivedBeforeCurrentFile + fileReceived
        let fraction: Double
        if totalBytes > 0 {
            fraction = min(1, Double(aggregateReceived) / Double(totalBytes))
        } else if expectedFileBytes > 0 {
            fraction = min(1, Double(fileReceived) / Double(expectedFileBytes))
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
}
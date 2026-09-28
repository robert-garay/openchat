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
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var wifi = false
        monitor.pathUpdateHandler = { path in
            wifi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            semaphore.signal()
        }
        let queue = DispatchQueue(label: "com.openchat.local-models.wifi-check")
        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 2)
        monitor.cancel()
        return wifi
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
        var received = 0

        for file in entry.files {
            guard let remoteURL = URL(string: file.url) else {
                throw LocalModelsError.invalidURL(file.url)
            }
            let destination = modelDir.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                throw LocalModelsError.downloadFailed("HTTP \(http.statusCode) for \(file.path)")
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)

            let digest = try LocalModelChecksum.sha256Hex(of: destination)
            guard digest.lowercased() == file.sha256.lowercased() else {
                try? FileManager.default.removeItem(at: modelDir)
                throw LocalModelsError.checksumMismatch(path: file.path)
            }

            received += file.bytes ?? (try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            let fraction = totalBytes > 0 ? Double(received) / Double(totalBytes) : 1
            progress(
                LocalModelDownloadProgress(
                    modelID: entry.id,
                    fractionCompleted: min(1, fraction),
                    receivedBytes: received,
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

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? modelDir.setResourceValues(values)
        _ = manifestVersion
    }
}

import Foundation

struct LocalModelsManifest: Codable, Sendable {
    var version: Int
    var minAppVersion: String?
    var models: [LocalModelManifestEntry]
}

struct LocalModelManifestEntry: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var mlxModelID: String
    var displayName: String
    var tier: String
    var intelligenceLevel: String
    var minRAMGB: Int
    var recommendedDevices: [String]
    var bytes: Int
    var sha256: String
    var backend: String
    var chatTemplate: String
    var files: [LocalModelManifestFile]
    var defaultForTier: Bool?
    var notRecommendedReason: String?

    var isDownloadable: Bool {
        notRecommendedReason == nil && !files.isEmpty
    }
}

struct LocalModelManifestFile: Codable, Sendable, Hashable {
    var path: String
    var url: String
    var sha256: String
    var bytes: Int?
}

enum LocalModelsManifestLoader {
    private static let allowedHosts: Set<String> = [
        "huggingface.co",
        "cdn-lfs.huggingface.co"
    ]

    static func loadBundled() throws -> LocalModelsManifest {
        guard let url = Bundle.main.url(forResource: "LocalModelsManifest", withExtension: "json") else {
            throw LocalModelsError.manifestMissing
        }
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(LocalModelsManifest.self, from: data)
        try validate(manifest)
        return manifest
    }

    static func validate(_ manifest: LocalModelsManifest) throws {
        for entry in manifest.models {
            for file in entry.files {
                guard let url = URL(string: file.url), url.scheme == "https" else {
                    throw LocalModelsError.invalidURL(file.url)
                }
                guard let host = url.host, allowedHosts.contains(host) else {
                    throw LocalModelsError.hostNotAllowed(url.host ?? file.url)
                }
            }
        }
    }

    static func entry(
        mlxModelID: String,
        in manifest: LocalModelsManifest
    ) -> LocalModelManifestEntry? {
        manifest.models.first { $0.mlxModelID == mlxModelID || $0.id == mlxModelID }
    }
}

enum LocalModelsError: LocalizedError {
    case manifestMissing
    case invalidURL(String)
    case hostNotAllowed(String)
    case insufficientRAM(requiredGB: Int)
    case checksumMismatch(path: String)
    case bundleChecksumMismatch
    case downloadFailed(String)
    case wifiRequired
    case modelNotReady
    case unsupportedAttachment

    var errorDescription: String? {
        switch self {
        case .manifestMissing:
            return "The on-device model catalog is missing from the app bundle."
        case .invalidURL(let url):
            return "Invalid download URL in catalog: \(url)"
        case .hostNotAllowed(let host):
            return "Downloads from \(host) are not allowed."
        case .insufficientRAM(let requiredGB):
            return "This model needs at least \(requiredGB) GB of device memory."
        case .checksumMismatch(let path):
            return "Download verification failed for \(path). Delete the partial download and try again."
        case .bundleChecksumMismatch:
            return "The installed model bundle failed verification. Delete it and download again."
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .wifiRequired:
            return "Connect to Wi‑Fi to download this model, or turn off “Wi‑Fi only” in On-Device Models settings."
        case .modelNotReady:
            return "The on-device model is not installed or still downloading."
        case .unsupportedAttachment:
            return "On-device models do not support images or file attachments in v1."
        }
    }
}

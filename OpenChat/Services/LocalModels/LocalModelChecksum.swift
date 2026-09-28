import CryptoKit
import Foundation

enum LocalModelChecksum {
    static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Stable bundle digest: SHA-256 over sorted `path` + file SHA-256 pairs.
    static func bundleDigest(modelDirectory: URL, relativePaths: [String]) throws -> String {
        var hasher = SHA256()
        for path in relativePaths.sorted() {
            let fileURL = modelDirectory.appendingPathComponent(path)
            let fileHash = try sha256Hex(of: fileURL)
            hasher.update(data: Data(path.utf8))
            hasher.update(data: Data(fileHash.utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

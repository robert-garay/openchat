import Foundation

enum LocalModelInstallState: String, Codable, Sendable {
    case notInstalled
    case downloading
    case ready
    case failed
}

struct LocalModelInstallRecord: Codable, Sendable, Equatable {
    var modelID: String
    var state: LocalModelInstallState
    var installedAt: Date?
    var bytesOnDisk: Int?
    var manifestVersion: Int?
    var lastError: String?
    var downloadedBytes: Int?
}

enum LocalModelInstallStateMachine {
    static func canStartDownload(from state: LocalModelInstallState) -> Bool {
        switch state {
        case .notInstalled, .failed:
            return true
        case .downloading, .ready:
            return false
        }
    }

    static func markDownloading(_ record: LocalModelInstallRecord) -> LocalModelInstallRecord {
        var copy = record
        copy.state = .downloading
        copy.lastError = nil
        copy.downloadedBytes = 0
        return copy
    }

    static func markReady(
        _ record: LocalModelInstallRecord,
        bytesOnDisk: Int,
        manifestVersion: Int
    ) -> LocalModelInstallRecord {
        var copy = record
        copy.state = .ready
        copy.installedAt = .now
        copy.bytesOnDisk = bytesOnDisk
        copy.manifestVersion = manifestVersion
        copy.lastError = nil
        copy.downloadedBytes = nil
        return copy
    }

    static func markFailed(_ record: LocalModelInstallRecord, error: String) -> LocalModelInstallRecord {
        var copy = record
        copy.state = .failed
        copy.lastError = error
        copy.downloadedBytes = nil
        return copy
    }
}

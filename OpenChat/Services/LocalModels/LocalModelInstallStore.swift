import Foundation

/// JSON persistence for on-device model install state under Application Support.
final class LocalModelInstallStore: Sendable {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        var root = base.appendingPathComponent("LocalModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appendingPathComponent("install-state.json")
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }

    func load() -> [String: LocalModelInstallRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        guard let records = try? decoder.decode([String: LocalModelInstallRecord].self, from: data) else { return [:] }
        return records
    }

    func save(_ records: [String: LocalModelInstallRecord]) throws {
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }

    func modelDirectory(for modelID: String) -> URL {
        let base = fileURL.deletingLastPathComponent()
        return base.appendingPathComponent(modelID, isDirectory: true)
    }
}

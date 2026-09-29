import Foundation
import Observation

enum LocalModelUserSettings {
    static let intelligencePreferenceKey = "com.openchat.localModels.intelligencePreference"
    static let wifiOnlyDownloadsKey = "com.openchat.localModels.wifiOnlyDownloads"
    static let onboardingInterestKey = "com.openchat.localModelsInterest"
}

@MainActor
@Observable
final class LocalModelStore {
    private(set) var manifest: LocalModelsManifest?
    private(set) var records: [String: LocalModelInstallRecord] = [:]
    private(set) var downloadProgress: LocalModelDownloadProgress?
    private(set) var loadError: String?

    private let installStore = LocalModelInstallStore()
    private var downloadTask: Task<Void, Never>?

    var intelligencePreference: IntelligencePreference {
        get {
            let raw = UserDefaults.standard.string(forKey: LocalModelUserSettings.intelligencePreferenceKey)
            return IntelligencePreference(rawValue: raw ?? "") ?? .everydayChat
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: LocalModelUserSettings.intelligencePreferenceKey)
        }
    }

    var wifiOnlyDownloads: Bool {
        get {
            if UserDefaults.standard.object(forKey: LocalModelUserSettings.wifiOnlyDownloadsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: LocalModelUserSettings.wifiOnlyDownloadsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: LocalModelUserSettings.wifiOnlyDownloadsKey)
        }
    }

    var deviceTier: DeviceTier {
        DeviceTier.from(physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
    }

    func bootstrap() {
        do {
            manifest = try LocalModelsManifestLoader.loadBundled()
            records = installStore.load()
            loadError = nil
        } catch {
            manifest = nil
            loadError = error.localizedDescription
        }
    }

    func record(for modelID: String) -> LocalModelInstallRecord {
        records[modelID] ?? LocalModelInstallRecord(modelID: modelID, state: .notInstalled)
    }

    var readyEntries: [LocalModelManifestEntry] {
        guard let manifest else { return [] }
        return manifest.models.filter { entry in
            record(for: entry.id).state == .ready
        }
    }

    func deviceContext(isOnWiFi: Bool? = nil) -> DeviceContext {
        DeviceContext.live(
            preference: intelligencePreference,
            wifiOnlyDownloads: wifiOnlyDownloads,
            isOnWiFi: isOnWiFi
        )
    }

    func recommendationResult(
        preference: IntelligencePreference? = nil,
        isOnWiFi: Bool? = nil
    ) -> ModelRecommendationResult? {
        guard let manifest else { return nil }
        var context = deviceContext(isOnWiFi: isOnWiFi)
        if let preference {
            context = context.withPreference(preference)
        }
        return LocalModelRecommendationEngine.recommend(manifest: manifest, context: context)
    }

    func recommendedPrimaryEntry() -> LocalModelManifestEntry? {
        guard let pick = recommendationResult()?.primary, !pick.isBlockedForDownload else {
            return recommendationResult()?.picks.first(where: { !$0.isBlockedForDownload })?.entry
        }
        return pick.entry
    }

    func compatibleDownloadableEntries() -> [LocalModelManifestEntry] {
        guard let manifest else { return [] }
        let ramGB = deviceTier.minRAMGB
        return manifest.models.filter { entry in
            entry.isDownloadable && entry.minRAMGB <= ramGB
        }
    }

    func syncProvider(into providerStore: ProviderStore) {
        let models = readyEntries.map { OnDeviceProvider.aiModel(from: $0) }
        providerStore.syncOnDeviceProvider(models: models)
    }

    func startDownload(entry: LocalModelManifestEntry, providerStore: ProviderStore) {
        guard let manifest else { return }
        let existing = record(for: entry.id)
        guard LocalModelInstallStateMachine.canStartDownload(from: existing.state) else { return }

        let context = deviceContext()
        switch context.storageAssessment(forModelBytes: entry.bytes) {
        case .insufficient(let available, let required):
            let message = String(
                localized: "Not enough free storage (\(Self.formatGB(available)) available, ~\(Self.formatGB(required)) required)."
            )
            records[entry.id] = LocalModelInstallStateMachine.markFailed(existing, error: message)
            persistRecords()
            return
        default:
            break
        }

        downloadTask?.cancel()
        records[entry.id] = LocalModelInstallStateMachine.markDownloading(existing)
        persistRecords()

        downloadTask = Task {
            do {
                try await LocalModelDownloadService.download(
                    entry: entry,
                    manifestVersion: manifest.version,
                    installStore: installStore,
                    wifiOnly: wifiOnlyDownloads
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                        if var record = self?.records[entry.id] {
                            record.downloadedBytes = progress.receivedBytes
                            self?.records[entry.id] = record
                        }
                    }
                }

                let dir = installStore.modelDirectory(for: entry.id)
                let bytes = directorySize(dir)
                records[entry.id] = LocalModelInstallStateMachine.markReady(
                    existing,
                    bytesOnDisk: bytes,
                    manifestVersion: manifest.version
                )
                downloadProgress = nil
                persistRecords()
                syncProvider(into: providerStore)
            } catch is CancellationError {
                records[entry.id] = LocalModelInstallStateMachine.markFailed(existing, error: "Cancelled")
                downloadProgress = nil
                persistRecords()
            } catch {
                records[entry.id] = LocalModelInstallStateMachine.markFailed(
                    existing,
                    error: error.localizedDescription
                )
                downloadProgress = nil
                persistRecords()
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadProgress = nil
    }

    func deleteModel(modelID: String, providerStore: ProviderStore) {
        let dir = installStore.modelDirectory(for: modelID)
        try? FileManager.default.removeItem(at: dir)
        records[modelID] = LocalModelInstallRecord(modelID: modelID, state: .notInstalled)
        persistRecords()
        syncProvider(into: providerStore)
        Task { await LocalMLXRuntime.shared.unloadIfLoaded(modelID: modelID) }
    }

    func installDirectory(for modelID: String) -> URL? {
        guard record(for: modelID).state == .ready else { return nil }
        return installStore.modelDirectory(for: modelID)
    }

    private func persistRecords() {
        try? installStore.save(records)
    }

    private static func formatGB(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
    }

    private func directorySize(_ url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += size
        }
        return total
    }
}

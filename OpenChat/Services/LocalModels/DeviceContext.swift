import Foundation

/// Performance bucket within a RAM tier (from `utsname().machine`, not marketing names).
enum ChipPerformanceClass: Int, Comparable, Sendable {
    case standard = 0
    case enhanced = 1
    case premium = 2

    static func < (lhs: ChipPerformanceClass, rhs: ChipPerformanceClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func from(machineIdentifier: String) -> ChipPerformanceClass {
        // ponytail: iPhone-only; "iPhone{major},{minor}" generation heuristic.
        guard machineIdentifier.hasPrefix("iPhone") else { return .standard }
        let rest = machineIdentifier.dropFirst("iPhone".count)
        guard let comma = rest.firstIndex(of: ",") else { return .standard }
        let major = Int(rest[..<comma]) ?? 0
        switch major {
        case ...13:
            return .standard
        case 14 ... 15:
            return .enhanced
        default:
            return .premium
        }
    }

    var rankingBias: Int { rawValue }
}

struct DeviceContext: Sendable, Equatable {
    static let downloadHeadroomBytes = 512 * 1_024 * 1_024

    let physicalMemoryBytes: UInt64
    let availableImportantDiskBytes: Int64?
    let machineIdentifier: String
    let chipPerformanceClass: ChipPerformanceClass
    let intelligencePreference: IntelligencePreference
    let isOnWiFi: Bool
    let wifiOnlyDownloads: Bool
    let thermalState: ProcessInfo.ThermalState
    let isLowPowerModeEnabled: Bool

    var deviceTier: DeviceTier {
        DeviceTier.from(physicalMemoryBytes: physicalMemoryBytes)
    }

    var capabilitySummary: String {
        let chipLabel: String
        switch chipPerformanceClass {
        case .standard:
            chipLabel = String(localized: "Standard performance")
        case .enhanced:
            chipLabel = String(localized: "Enhanced performance")
        case .premium:
            chipLabel = String(localized: "High performance")
        }
        return "\(chipLabel) · \(deviceTier.displayLabel)"
    }

    func storageAssessment(forModelBytes modelBytes: Int) -> StorageFit {
        guard let available = availableImportantDiskBytes else {
            return .unknown
        }
        let required = Int64(modelBytes) + Int64(Self.downloadHeadroomBytes)
        if available < required {
            return .insufficient(
                availableBytes: available,
                requiredBytes: required
            )
        }
        if available < required + Int64(Self.downloadHeadroomBytes) {
            return .tight(availableBytes: available, requiredBytes: required)
        }
        return .comfortable(availableBytes: available, requiredBytes: required)
    }

    enum StorageFit: Equatable, Sendable {
        case unknown
        case comfortable(availableBytes: Int64, requiredBytes: Int64)
        case tight(availableBytes: Int64, requiredBytes: Int64)
        case insufficient(availableBytes: Int64, requiredBytes: Int64)
    }

    static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    static func availableImportantDiskBytes() -> Int64? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return try? docs?.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    func withPreference(_ preference: IntelligencePreference) -> DeviceContext {
        DeviceContext(
            physicalMemoryBytes: physicalMemoryBytes,
            availableImportantDiskBytes: availableImportantDiskBytes,
            machineIdentifier: machineIdentifier,
            chipPerformanceClass: chipPerformanceClass,
            intelligencePreference: preference,
            isOnWiFi: isOnWiFi,
            wifiOnlyDownloads: wifiOnlyDownloads,
            thermalState: thermalState,
            isLowPowerModeEnabled: isLowPowerModeEnabled
        )
    }

    static func live(
        preference: IntelligencePreference,
        wifiOnlyDownloads: Bool,
        isOnWiFi: Bool? = nil
    ) -> DeviceContext {
        let wifi = isOnWiFi ?? LocalModelDownloadService.isOnWiFi()
        let machine = machineIdentifier()
        return DeviceContext(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            availableImportantDiskBytes: availableImportantDiskBytes(),
            machineIdentifier: machine,
            chipPerformanceClass: ChipPerformanceClass.from(machineIdentifier: machine),
            intelligencePreference: preference,
            isOnWiFi: wifi,
            wifiOnlyDownloads: wifiOnlyDownloads,
            thermalState: ProcessInfo.processInfo.thermalState,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}

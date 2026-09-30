import Foundation

/// Curated on-device catalog vendors (Meta / Qwen / Microsoft only).
enum LocalModelVendor: String, CaseIterable, Identifiable, Sendable {
    case meta
    case qwen
    case microsoft

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .meta:
            return String(localized: "Meta")
        case .qwen:
            return String(localized: "Qwen")
        case .microsoft:
            return String(localized: "Microsoft")
        }
    }

    var logoAssetName: String? {
        switch self {
        case .meta:
            return "ProviderLogoMeta"
        case .qwen:
            return "ProviderLogoAlibabaCloud"
        case .microsoft:
            return "ProviderLogoMicrosoft"
        }
    }

    var symbolName: String {
        switch self {
        case .meta:
            return "infinity"
        case .qwen:
            return "cloud.fill"
        case .microsoft:
            return "square.grid.2x2.fill"
        }
    }

    static func from(entry: LocalModelManifestEntry) -> LocalModelVendor? {
        let key = entry.mlxModelID.lowercased()
        if key.contains("llama") { return .meta }
        if key.contains("qwen") { return .qwen }
        if key.contains("phi") { return .microsoft }
        return nil
    }

    static func groupedDownloadableEntries(
        from entries: [LocalModelManifestEntry]
    ) -> [(vendor: LocalModelVendor, models: [LocalModelManifestEntry])] {
        var buckets: [LocalModelVendor: [LocalModelManifestEntry]] = [:]
        for entry in entries {
            guard let vendor = from(entry: entry) else { continue }
            buckets[vendor, default: []].append(entry)
        }
        return LocalModelVendor.allCases.compactMap { vendor in
            guard let models = buckets[vendor], !models.isEmpty else { return nil }
            let sorted = models.sorted { lhs, rhs in
                if lhs.bytes != rhs.bytes { return lhs.bytes < rhs.bytes }
                return lhs.displayName < rhs.displayName
            }
            return (vendor, sorted)
        }
    }
}

extension LocalModelManifestEntry {
    var performanceTierLabel: RecommendationPickLabel {
        switch intelligenceLevel {
        case "quick":
            return .fast
        case "everyday":
            return .balanced
        case "best":
            return .strongest
        default:
            return .alternative
        }
    }
}

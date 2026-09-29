import Foundation

extension LocalModelRecommendationEngine {
    static func recommend(
        manifest: LocalModelsManifest,
        context: DeviceContext
    ) -> ModelRecommendationResult {
        let tier = context.deviceTier
        let catalogOrder = recommendedModels(
            deviceTier: tier,
            preference: context.intelligencePreference
        ).map(\.mlxModelID)

        let downloadable = manifest.models.filter { entry in
            entry.isDownloadable && entry.minRAMGB <= tier.minRAMGB
        }

        var scored: [(entry: LocalModelManifestEntry, score: Int)] = []
        for entry in downloadable {
            var score = 0
            if let index = catalogOrder.firstIndex(of: entry.mlxModelID) {
                score += 1_000 - index * 10
            } else if catalogOrder.contains(where: { entry.mlxModelID.hasPrefix($0) || $0.hasPrefix(entry.mlxModelID) }) {
                score += 100
            }
            score += min(entry.minRAMGB, tier.minRAMGB) * 5
            score += context.chipPerformanceClass.rankingBias * 3
            if context.intelligencePreference == .quickReplies {
                score -= entry.bytes / 50_000_000
            } else if context.intelligencePreference == .bestOnDevice {
                score += entry.bytes / 80_000_000
            }
            scored.append((entry, score))
        }

        scored.sort { $0.score > $1.score }

        var orderedEntries: [LocalModelManifestEntry] = []
        var seen = Set<String>()
        for id in catalogOrder {
            if let entry = LocalModelsManifestLoader.entry(mlxModelID: id, in: manifest),
               entry.isDownloadable,
               seen.insert(entry.id).inserted {
                orderedEntries.append(entry)
            }
        }
        for item in scored where seen.insert(item.entry.id).inserted {
            orderedEntries.append(item.entry)
        }

        let maxPicks = min(3, orderedEntries.count)
        let pickEntries = Array(orderedEntries.prefix(maxPicks))

        let picks: [RankedModelRecommendation] = pickEntries.enumerated().map { index, entry in
            let label = pickLabel(index: index, preference: context.intelligencePreference, total: pickEntries.count)
            let fit = context.storageAssessment(forModelBytes: entry.bytes)
            let blocked: Bool
            let blockReason: String?
            switch fit {
            case .insufficient(let available, let required):
                blocked = true
                blockReason = storageBlockMessage(available: available, required: required)
            default:
                blocked = false
                blockReason = nil
            }
            return RankedModelRecommendation(
                entry: entry,
                pickLabel: label,
                isBlockedForDownload: blocked,
                blockReason: blockReason
            )
        }

        let reasons = buildReasons(context: context, picks: picks)

        return ModelRecommendationResult(
            picks: picks,
            reasons: reasons,
            deviceSummary: context.capabilitySummary
        )
    }

    private static func pickLabel(
        index: Int,
        preference: IntelligencePreference,
        total: Int
    ) -> RecommendationPickLabel {
        if index == 0 {
            switch preference {
            case .quickReplies:
                return .fast
            case .everydayChat:
                return .balanced
            case .bestOnDevice:
                return .strongest
            }
        }
        if index == 1, total >= 2, preference == .bestOnDevice {
            return .balanced
        }
        return .alternative
    }

    private static func buildReasons(
        context: DeviceContext,
        picks: [RankedModelRecommendation]
    ) -> [RecommendationReason] {
        var reasons: [RecommendationReason] = []

        reasons.append(
            RecommendationReason(
                kind: .ram,
                message: String(
                    localized: "Your iPhone reports \(context.deviceTier.displayLabel) RAM (\(context.machineIdentifier))."
                )
            )
        )

        reasons.append(
            RecommendationReason(
                kind: .chip,
                message: String(
                    localized: "Chip class: \(chipClassExplanation(context.chipPerformanceClass)) for ranking within your RAM tier."
                )
            )
        )

        reasons.append(
            RecommendationReason(
                kind: .preference,
                message: String(
                    localized: "Preference: \(context.intelligencePreference.title) — \(context.intelligencePreference.subtitle)"
                )
            )
        )

        if let primary = picks.first {
            let gb = Double(primary.entry.bytes) / 1_073_741_824.0
            reasons.append(
                RecommendationReason(
                    kind: .downloadSize,
                    message: String(format: String(localized: "Top pick download size: %.1f GB."), gb)
                )
            )
        }

        switch context.storageAssessment(forModelBytes: picks.first?.entry.bytes ?? 0) {
        case .unknown:
            reasons.append(
                RecommendationReason(
                    kind: .storage,
                    message: String(localized: "Free storage could not be read; download may fail if space is low.")
                )
            )
        case .comfortable(let available, let required):
            reasons.append(
                RecommendationReason(
                    kind: .storage,
                    message: String(
                        localized: "Storage: \(formatGB(available)) free; need about \(formatGB(required)) including headroom."
                    )
                )
            )
        case .tight(let available, let required):
            reasons.append(
                RecommendationReason(
                    kind: .warning,
                    message: String(
                        localized: "Storage is tight (\(formatGB(available)) free, ~\(formatGB(required)) needed). Free space before downloading."
                    )
                )
            )
        case .insufficient(let available, let required):
            reasons.append(
                RecommendationReason(
                    kind: .storage,
                    message: storageBlockMessage(available: available, required: required)
                )
            )
        }

        if context.wifiOnlyDownloads, !context.isOnWiFi {
            reasons.append(
                RecommendationReason(
                    kind: .warning,
                    message: String(localized: "Wi‑Fi only downloads are on and you are not on Wi‑Fi.")
                )
            )
        }

        if context.thermalState == .serious || context.thermalState == .critical {
            reasons.append(
                RecommendationReason(
                    kind: .warning,
                    message: String(localized: "Device is thermally stressed; on-device models may run slower until it cools.")
                )
            )
        }

        if context.isLowPowerModeEnabled {
            reasons.append(
                RecommendationReason(
                    kind: .warning,
                    message: String(localized: "Low Power Mode is on; responses may be slower.")
                )
            )
        }

        return reasons
    }

    private static func chipClassExplanation(_ chip: ChipPerformanceClass) -> String {
        switch chip {
        case .standard:
            return String(localized: "standard")
        case .enhanced:
            return String(localized: "enhanced")
        case .premium:
            return String(localized: "premium")
        }
    }

    private static func storageBlockMessage(available: Int64, required: Int64) -> String {
        String(
            localized: "Not enough free storage (\(formatGB(available)) available, ~\(formatGB(required)) required including headroom)."
        )
    }

    private static func formatGB(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
    }
}

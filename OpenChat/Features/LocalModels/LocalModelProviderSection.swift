import SwiftUI

struct LocalModelProviderSection: View {
    let vendor: LocalModelVendor
    let models: [LocalModelManifestEntry]
    @Binding var expandedVendorID: String?

    @Environment(LocalModelStore.self) private var localModelStore
    @Environment(ProviderStore.self) private var providerStore

    private var isExpanded: Bool {
        expandedVendorID == vendor.id
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedVendorID = isExpanded ? nil : vendor.id
            }
        } label: {
            HStack(spacing: 12) {
                ProviderLogoView(
                    logoAssetName: vendor.logoAssetName,
                    symbolName: vendor.symbolName,
                    tint: vendorTint,
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(vendor.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(modelCountLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)

        if isExpanded {
            ForEach(models) { entry in
                LocalModelDownloadRow(entry: entry)
            }
        }
    }

    private var modelCountLabel: String {
        let count = models.count
        if count == 1 {
            return String(localized: "1 downloadable model")
        }
        return String(localized: "\(count) downloadable models")
    }

    private var vendorTint: Color {
        switch vendor {
        case .meta:
            return Color(red: 0.0, green: 0.47, blue: 0.95)
        case .qwen:
            return Color(red: 1.0, green: 0.48, blue: 0.0)
        case .microsoft:
            return Color(red: 0.0, green: 0.64, blue: 0.88)
        }
    }
}

struct LocalModelDownloadRow: View {
    let entry: LocalModelManifestEntry

    @Environment(LocalModelStore.self) private var localModelStore
    @Environment(ProviderStore.self) private var providerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    LocalModelTierBadge(label: entry.performanceTierLabel, compact: true)
                    Text(entry.displayName)
                        .font(.body.weight(.medium))
                    Text(formattedBytes(entry.bytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                stateControl
            }

            if let progress = localModelStore.downloadProgress(for: entry.id) {
                ProgressView(value: progress.fractionCompleted)
                Text(progressLabel(progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = localModelStore.record(for: entry.id).lastError,
               localModelStore.record(for: entry.id).state == .failed {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stateControl: some View {
        let state = localModelStore.record(for: entry.id).state
        switch state {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        case .downloading:
            Button("Cancel", role: .destructive) {
                localModelStore.cancelDownload(modelID: entry.id)
            }
            .font(.caption)
        default:
            Button("Download") {
                localModelStore.startDownload(entry: entry, providerStore: providerStore)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(downloadDisabled)
        }
    }

    private var downloadDisabled: Bool {
        downloadBlockReason != nil
    }

    private var downloadBlockReason: String? {
        if entry.minRAMGB > localModelStore.deviceTier.minRAMGB {
            return String(localized: "Needs ~\(entry.minRAMGB) GB RAM")
        }
        if let pick = localModelStore.recommendationResult()?.picks.first(where: { $0.entry.id == entry.id }),
           pick.isBlockedForDownload {
            return pick.blockReason
        }
        return nil
    }

    private func formattedBytes(_ bytes: Int) -> String {
        String(format: "%.1f GB download", Double(bytes) / 1_073_741_824.0)
    }

    private func progressLabel(_ progress: LocalModelDownloadProgress) -> String {
        let percent = Int(progress.fractionCompleted * 100)
        return "\(percent)% · \(formattedTransfer(progress.receivedBytes)) of \(formattedTransfer(progress.totalBytes))"
    }

    private func formattedTransfer(_ bytes: Int) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
        }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576.0)
    }
}

import SwiftUI

struct LocalModelRecommendationSection: View {
    let result: ModelRecommendationResult
    @Binding var selectedEntryID: String?
    @State private var showWhy = false

    var body: some View {
        Section {
            Text(result.deviceSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        Section("Recommended for you") {
            ForEach(result.picks) { pick in
                Button {
                    if !pick.isBlockedForDownload {
                        selectedEntryID = pick.entry.id
                    }
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pick.pickLabel.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(pick.entry.displayName)
                                .font(.body.weight(.medium))
                            Text(formattedBytes(pick.entry.bytes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if pick.isBlockedForDownload, let reason = pick.blockReason {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        if selectedEntryID == pick.entry.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(pick.isBlockedForDownload)
            }
        }

        Section {
            DisclosureGroup("Why these models?", isExpanded: $showWhy) {
                ForEach(result.reasons) { reason in
                    Label(reason.message, systemImage: icon(for: reason.kind))
                        .font(.caption)
                        .foregroundStyle(reason.kind == .warning ? Color.orange : Color.secondary)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    private func icon(for kind: RecommendationReason.Kind) -> String {
        switch kind {
        case .ram:
            return "memorychip"
        case .storage:
            return "externaldrive"
        case .chip:
            return "cpu"
        case .preference:
            return "slider.horizontal.3"
        case .downloadSize:
            return "arrow.down.circle"
        case .warning:
            return "exclamationmark.triangle"
        }
    }

    private func formattedBytes(_ bytes: Int) -> String {
        String(format: "%.1f GB download", Double(bytes) / 1_073_741_824.0)
    }
}

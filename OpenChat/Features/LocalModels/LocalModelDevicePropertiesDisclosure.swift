import SwiftUI

struct LocalModelDevicePropertiesDisclosure: View {
    let context: DeviceContext
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("This iPhone", isExpanded: $isExpanded) {
            LabeledContent("RAM tier", value: context.deviceTier.displayLabel)
            LabeledContent("Physical RAM", value: formattedRAM(context.physicalMemoryBytes))
            if let disk = context.availableImportantDiskBytes {
                LabeledContent("Free storage", value: formattedDisk(disk))
            }
            LabeledContent("Chip ID", value: context.machineIdentifier)
            LabeledContent("Chip class", value: chipLabel(context.chipPerformanceClass))
            LabeledContent("Preference", value: context.intelligencePreference.title)
            LabeledContent("Wi‑Fi only downloads", value: context.wifiOnlyDownloads ? "On" : "Off")
            if context.isOnWiFi {
                Label("On Wi‑Fi", systemImage: "wifi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    private func formattedRAM(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
    }

    private func formattedDisk(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
    }

    private func chipLabel(_ chip: ChipPerformanceClass) -> String {
        switch chip {
        case .standard:
            return String(localized: "Standard")
        case .enhanced:
            return String(localized: "Enhanced")
        case .premium:
            return String(localized: "Premium")
        }
    }
}

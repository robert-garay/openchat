import Foundation

enum OnDeviceProvider {
    static let providerID = "openchat-ondevice"
    static let templateID = "openchat-ondevice"

    static func configuredProvider(models: [AIModel]) -> ConfiguredProvider {
        ConfiguredProvider(
            id: providerID,
            templateID: templateID,
            name: String(localized: "On This Device"),
            symbolName: "iphone.gen3",
            tint: "#34C759",
            baseURL: "openchat-ondevice://local",
            apiFormat: .openAI,
            models: models,
            requiresAPIKey: false,
            isEnabled: true,
            customLogoID: nil,
            inferenceBackend: .localMLX
        )
    }

    static func aiModel(from entry: LocalModelManifestEntry) -> AIModel {
        let sizeGB = Double(entry.bytes) / 1_073_741_824.0
        let sizeLabel = String(format: "%.1f GB", sizeGB)
        return AIModel(
            id: entry.mlxModelID,
            displayName: entry.displayName,
            subtitle: String(localized: "On device · \(sizeLabel) · 4-bit"),
            capabilities: [],
            reasoningConfig: nil
        )
    }
}

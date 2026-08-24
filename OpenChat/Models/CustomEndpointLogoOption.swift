import Foundation

/// A curated brand mark a user can pick for a custom endpoint (self-hosted server,
/// internal gateway, or a hosted cloud that isn't in the built-in template list).
/// Purely cosmetic — has no bearing on `baseURL` or `apiFormat`.
struct CustomEndpointLogoOption: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var logoAssetName: String

    static let all: [CustomEndpointLogoOption] = [
        CustomEndpointLogoOption(id: "runpod", name: "RunPod", logoAssetName: "ProviderLogoRunPod"),
        CustomEndpointLogoOption(id: "modal", name: "Modal", logoAssetName: "ProviderLogoModal"),
        CustomEndpointLogoOption(id: "together", name: "Together AI", logoAssetName: "ProviderLogoTogetherAI"),
        CustomEndpointLogoOption(id: "fireworks", name: "Fireworks AI", logoAssetName: "ProviderLogoFireworksAI"),
        CustomEndpointLogoOption(id: "groq", name: "Groq", logoAssetName: "ProviderLogoGroq"),
        CustomEndpointLogoOption(id: "huggingface", name: "Hugging Face", logoAssetName: "ProviderLogoHuggingFace"),
        CustomEndpointLogoOption(id: "replicate", name: "Replicate", logoAssetName: "ProviderLogoReplicate"),
        CustomEndpointLogoOption(id: "baseten", name: "Baseten", logoAssetName: "ProviderLogoBaseten"),
        CustomEndpointLogoOption(id: "cerebras", name: "Cerebras", logoAssetName: "ProviderLogoCerebras"),
        CustomEndpointLogoOption(id: "blackforestlabs", name: "Black Forest Labs", logoAssetName: "ProviderLogoBlackForestLabs"),
    ]

    static func option(for id: String?) -> CustomEndpointLogoOption? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

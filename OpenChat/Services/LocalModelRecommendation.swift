import Foundation

/// RAM bucket derived from `ProcessInfo.processInfo.physicalMemory`.
enum DeviceTier: Int, Comparable, Sendable {
    case legacy4GB = 4
    case standard6GB = 6
    case performance8GB = 8
    case high12GB = 12

    static func < (lhs: DeviceTier, rhs: DeviceTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func from(physicalMemoryBytes: UInt64) -> DeviceTier {
        let gib = Double(physicalMemoryBytes) / 1_073_741_824.0
        switch gib {
        case ..<5.5:
            return .legacy4GB
        case ..<7.5:
            return .standard6GB
        case ..<10.5:
            return .performance8GB
        default:
            return .high12GB
        }
    }

    var minRAMGB: Int { rawValue }

    var displayLabel: String {
        switch self {
        case .legacy4GB:
            return String(localized: "4 GB class")
        case .standard6GB:
            return String(localized: "6 GB class")
        case .performance8GB:
            return String(localized: "8 GB class")
        case .high12GB:
            return String(localized: "12 GB+ class")
        }
    }
}

/// Maps to onboarding copy: Quick replies / Everyday chat / Best on your phone.
enum IntelligencePreference: String, CaseIterable, Sendable {
    case quickReplies = "quick"
    case everydayChat = "everyday"
    case bestOnDevice = "best"
}

struct LocalModelRecommendation: Equatable, Sendable {
    let mlxModelID: String
    let minRAMGB: Int
}

enum LocalModelRecommendationEngine {
    // ponytail: static table until manifest drives catalog in Phase 1.
    private static let catalog: [DeviceTier: [IntelligencePreference: [LocalModelRecommendation]]] = [
        .legacy4GB: [
            .quickReplies: [
                LocalModelRecommendation(mlxModelID: "mlx-community/Qwen2.5-0.5B-Instruct-4bit", minRAMGB: 4),
                LocalModelRecommendation(mlxModelID: "mlx-community/Qwen3-0.6B-4bit", minRAMGB: 4)
            ],
            .everydayChat: [
                LocalModelRecommendation(mlxModelID: "mlx-community/Qwen3-0.6B-4bit", minRAMGB: 4)
            ],
            .bestOnDevice: [
                LocalModelRecommendation(mlxModelID: "mlx-community/Qwen3-0.6B-4bit", minRAMGB: 4)
            ]
        ],
        .standard6GB: [
            .quickReplies: [
                LocalModelRecommendation(mlxModelID: "mlx-community/Llama-3.2-1B-Instruct-4bit", minRAMGB: 6),
                LocalModelRecommendation(mlxModelID: "mlx-community/Qwen3-0.6B-4bit", minRAMGB: 6)
            ],
            .everydayChat: [
                LocalModelRecommendation(mlxModelID: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", minRAMGB: 6),
                LocalModelRecommendation(mlxModelID: "mlx-community/Llama-3.2-1B-Instruct-4bit", minRAMGB: 6)
            ],
            .bestOnDevice: [
                LocalModelRecommendation(mlxModelID: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", minRAMGB: 6)
            ]
        ],
        .performance8GB: [
            .quickReplies: [
                LocalModelRecommendation(mlxModelID: "mlx-community/Llama-3.2-1B-Instruct-4bit", minRAMGB: 6),
                LocalModelRecommendation(mlxModelID: "mlx-community/Qwen3-0.6B-4bit", minRAMGB: 4)
            ],
            .everydayChat: [
                LocalModelRecommendation(mlxModelID: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", minRAMGB: 6),
                LocalModelRecommendation(mlxModelID: "mlx-community/Phi-3.5-mini-instruct-4bit", minRAMGB: 8)
            ],
            .bestOnDevice: [
                LocalModelRecommendation(mlxModelID: "mlx-community/Qwen2.5-3B-Instruct-4bit", minRAMGB: 8),
                LocalModelRecommendation(mlxModelID: "mlx-community/Llama-3.2-3B-Instruct-4bit", minRAMGB: 8),
                LocalModelRecommendation(mlxModelID: "mlx-community/Qwen3-4B-Instruct-2507-4bit", minRAMGB: 8)
            ]
        ],
        .high12GB: [
            .quickReplies: [
                LocalModelRecommendation(mlxModelID: "mlx-community/Llama-3.2-1B-Instruct-4bit", minRAMGB: 6)
            ],
            .everydayChat: [
                LocalModelRecommendation(mlxModelID: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", minRAMGB: 6),
                LocalModelRecommendation(mlxModelID: "mlx-community/Phi-3.5-mini-instruct-4bit", minRAMGB: 8)
            ],
            .bestOnDevice: [
                LocalModelRecommendation(mlxModelID: "mlx-community/Qwen3-4B-Instruct-2507-4bit", minRAMGB: 8),
                LocalModelRecommendation(mlxModelID: "mlx-community/Qwen2.5-3B-Instruct-4bit", minRAMGB: 8)
            ]
        ]
    ]

    static func recommendedModels(
        deviceTier: DeviceTier,
        preference: IntelligencePreference
    ) -> [LocalModelRecommendation] {
        let candidates = catalog[deviceTier]?[preference] ?? []
        return candidates.filter { $0.minRAMGB <= deviceTier.minRAMGB }
    }

    static func recommendedModels(
        physicalMemoryBytes: UInt64,
        preference: IntelligencePreference
    ) -> [LocalModelRecommendation] {
        let tier = DeviceTier.from(physicalMemoryBytes: physicalMemoryBytes)
        return recommendedModels(deviceTier: tier, preference: preference)
    }

    static func primaryModelID(
        physicalMemoryBytes: UInt64,
        preference: IntelligencePreference
    ) -> String? {
        recommendedModels(physicalMemoryBytes: physicalMemoryBytes, preference: preference).first?.mlxModelID
    }
}

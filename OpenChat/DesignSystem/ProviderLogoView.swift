import SwiftUI
import UIKit

/// Renders an official provider logo when available, otherwise the SF Symbol fallback.
struct ProviderLogoView: View {
    var logoAssetName: String?
    var symbolName: String
    var tint: Color
    var size: CGFloat = 32
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let logoAssetName, UIImage(named: logoAssetName) != nil {
                Image(logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: symbolName)
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(tint)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

enum ProviderLogo {
    /// Asset catalog name for a built-in provider id / template id.
    static func assetName(for id: String?) -> String? {
        guard let id else { return nil }
        switch id {
        case "deepseek": return "ProviderLogoDeepSeek"
        case "mistral": return "ProviderLogoMistral"
        case "qwen": return "ProviderLogoAlibabaCloud"
        case "moonshot": return "ProviderLogoMoonshot"
        case "zhipu": return "ProviderLogoZai"
        case "yi": return "ProviderLogoYi"
        case "openai": return "ProviderLogoOpenAI"
        case "anthropic": return "ProviderLogoAnthropic"
        case "google": return "ProviderLogoGoogle" // Gemini mark kept intentionally
        case "openrouter": return "ProviderLogoOpenRouter"
        case "cheaperinference": return "ProviderLogoCheaperInference"
        default: return nil
        }
    }
}

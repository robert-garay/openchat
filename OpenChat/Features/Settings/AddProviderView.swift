import SwiftUI

/// Lets the user pick a curated provider to connect, or wire up any custom
/// OpenAI-compatible endpoint (a self-hosted Ollama server, LM Studio, a
/// company-internal gateway, or a brand-new model that isn't in the list yet).
struct AddProviderView: View {
    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.dismiss) private var dismiss

    private var availableTemplates: [ProviderTemplate] {
        ProviderTemplate.all.filter { template in
            !providerStore.providers.contains { $0.id == template.id }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(availableTemplates) { template in
                        NavigationLink {
                            ProviderKeyEntryView(template: template) { dismiss() }
                        } label: {
                            ProviderTemplateRow(template: template)
                        }
                    }
                } header: {
                    Text("Model Providers")
                } footer: {
                    Text("Includes leading Chinese open models — DeepSeek, Qwen, Kimi, and GLM — alongside OpenAI, Claude, Gemini, and OpenRouter.")
                }

                Section {
                    NavigationLink {
                        CustomProviderView { dismiss() }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Custom Endpoint")
                                    .font(.body.weight(.medium))
                                Text("Ollama, LM Studio, vLLM, or any OpenAI-compatible API")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            ProviderLogoView(
                                logoAssetName: nil,
                                symbolName: "server.rack",
                                tint: Color(.secondaryLabel),
                                size: 32
                            )
                        }
                    }
                }
            }
            .navigationTitle("Add a Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct ProviderTemplateRow: View {
    let template: ProviderTemplate

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(template.name)
                        .font(.body.weight(.medium))
                    if let region = template.region {
                        Text(region)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: template.tint).opacity(0.15), in: Capsule())
                            .foregroundStyle(Color(hex: template.tint))
                    }
                }
                Text(template.defaultModels.first?.displayName ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            ProviderLogoView(
                logoAssetName: template.logoAssetName,
                symbolName: template.symbolName,
                tint: Color(hex: template.tint),
                size: 32
            )
        }
    }
}

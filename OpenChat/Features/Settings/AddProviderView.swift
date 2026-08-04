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
                }

                Section {
                    NavigationLink {
                        CustomProviderView { dismiss() }
                    } label: {
                        Label {
                            Text("Custom Endpoint")
                                .font(.body.weight(.medium))
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
            .navigationTitle("Add a Provider")
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
            Text(template.name)
                .font(.body.weight(.medium))
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

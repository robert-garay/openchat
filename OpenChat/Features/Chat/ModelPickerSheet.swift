import SwiftUI

struct ModelPickerSheet: View {
    let currentProviderID: String
    let currentModelID: String
    let onSelect: (String, String) -> Void

    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(providerStore.enabledProviders) { provider in
                    Section {
                        ForEach(provider.models) { model in
                            Button {
                                Haptics.light()
                                onSelect(provider.id, model.id)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName)
                                            .foregroundStyle(.primary)
                                        if let subtitle = model.subtitle {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if provider.id == currentProviderID && model.id == currentModelID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: 8) {
                            ProviderLogoView(
                                logoAssetName: provider.logoAssetName,
                                symbolName: provider.symbolName,
                                tint: Color(hex: provider.tint),
                                size: 20,
                                cornerRadius: 5
                            )
                            Text(provider.name)
                        }
                        .foregroundStyle(Color(hex: provider.tint))
                        .textCase(nil)
                    }
                }
            }
            .navigationTitle("Choose a Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

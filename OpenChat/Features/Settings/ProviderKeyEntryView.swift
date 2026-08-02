import SwiftUI

struct ProviderKeyEntryView: View {
    let template: ProviderTemplate
    var onSaved: () -> Void

    @Environment(ProviderStore.self) private var providerStore
    @State private var apiKey: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    ProviderLogoView(
                        logoAssetName: template.logoAssetName,
                        symbolName: template.symbolName,
                        tint: Color(hex: template.tint),
                        size: 56,
                        cornerRadius: 16
                    )
                    Text(template.name)
                        .font(.title3.weight(.semibold))
                    Text("Your API key is stored securely in the iOS Keychain and never leaves your device except to call \(template.name) directly.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                SecureField(template.apiKeyPlaceholder, text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($fieldFocused)
            } header: {
                Text("API Key")
            } footer: {
                if let url = template.keyHelpURL {
                    Link("Get an API key from \(template.name) →", destination: url)
                }
            }

            Section("Available Models") {
                ForEach(template.defaultModels) { model in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName)
                        if let subtitle = model.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { fieldFocused = true }
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if template.id == "openrouter" {
            providerStore.grantFreeModelsAccess(apiKey: trimmed)
            providerStore.refreshOpenRouterModelsIfNeeded(force: true)
        } else {
            let provider = ConfiguredProvider.fromTemplate(template)
            providerStore.addFromTemplate(template)
            providerStore.setAPIKey(trimmed, for: provider)
        }
        Haptics.success()
        onSaved()
    }
}

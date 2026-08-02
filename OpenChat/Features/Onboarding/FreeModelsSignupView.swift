import SwiftUI

/// First-run signup that grants OpenRouter free-model access with a single API key.
struct FreeModelsSignupView: View {
    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @FocusState private var fieldFocused: Bool

    private var template: ProviderTemplate? {
        ProviderTemplate.template(for: "openrouter")
    }

    private var freeModels: [AIModel] {
        ProviderTemplate.openRouterFreeModels
    }

    private var canSave: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        if let template {
                            ProviderLogoView(
                                logoAssetName: template.logoAssetName,
                                symbolName: template.symbolName,
                                tint: Color(hex: template.tint),
                                size: 56,
                                cornerRadius: 16
                            )
                        }
                        Text("Free Models")
                            .font(.title3.weight(.semibold))
                        Text("Paste a free OpenRouter API key to unlock free models on signup. Your key stays in the iOS Keychain and is only used to call OpenRouter directly.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    SecureField(template?.apiKeyPlaceholder ?? "sk-or-...", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($fieldFocused)
                } header: {
                    Text("OpenRouter API Key")
                } footer: {
                    if let url = template?.keyHelpURL {
                        Link("Create a free OpenRouter API key →", destination: url)
                    }
                }

                Section("Included Free Models") {
                    ForEach(freeModels) { model in
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
            .navigationTitle("Sign Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Chatting") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear { fieldFocused = true }
        }
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        providerStore.grantFreeModelsAccess(apiKey: trimmed)
        providerStore.refreshOpenRouterModelsIfNeeded(force: true)
        Haptics.success()
        dismiss()
    }
}

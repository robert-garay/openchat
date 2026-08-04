import SwiftUI

/// Adds any OpenAI-compatible endpoint: a self-hosted Ollama/LM Studio/vLLM
/// server, an internal gateway, or a brand-new hosted model that isn't in
/// the curated list yet.
struct CustomProviderView: View {
    var onSaved: () -> Void

    @Environment(ProviderStore.self) private var providerStore
    @State private var name = ""
    @State private var baseURL = ""
    @State private var modelsText = ""
    @State private var requiresAPIKey = false
    @State private var apiKey = ""

    private var models: [AIModel] {
        modelsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { AIModel(id: $0, displayName: $0) }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        URL(string: baseURL) != nil &&
        !models.isEmpty &&
        (!requiresAPIKey || !apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        Form {
            Section("Endpoint") {
                TextField("Name (e.g. My Ollama Server)", text: $name)
                TextField("Base URL", text: $baseURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Section {
                TextField("model-a, model-b, model-c", text: $modelsText, axis: .vertical)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Model IDs")
            } footer: {
                Text("Comma-separated model IDs exactly as the endpoint expects them, e.g. \"llama3.1, qwen2.5:14b\".")
            }

            Section {
                Toggle("Requires API Key", isOn: $requiresAPIKey.animation())
                if requiresAPIKey {
                    SecureField("API Key", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
        }
        .navigationTitle("Custom Endpoint")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespaces)
        providerStore.addCustom(name: trimmedName, baseURL: trimmedURL, models: models, requiresAPIKey: requiresAPIKey)
        if requiresAPIKey, let added = providerStore.providers.last {
            providerStore.setAPIKey(apiKey.trimmingCharacters(in: .whitespaces), for: added)
        }
        Haptics.success()
        onSaved()
    }
}

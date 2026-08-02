import SwiftUI

struct ProviderDetailView: View {
    @State var provider: ConfiguredProvider

    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var newModelID: String = ""
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $provider.isEnabled)
                    .onChange(of: provider.isEnabled) { _, _ in providerStore.update(provider) }
            }

            Section {
                TextField("Base URL", text: $provider.baseURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { providerStore.update(provider) }
            } header: {
                Text("Endpoint")
            }

            if provider.requiresAPIKey {
                Section {
                    SecureField(providerStore.apiKey(for: provider) == nil ? "Add API key" : "Update API key", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Save Key") {
                        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        providerStore.setAPIKey(apiKey, for: provider)
                        apiKey = ""
                        Haptics.success()
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("API Key")
                } footer: {
                    if let url = provider.template?.keyHelpURL {
                        Link("Get an API key from \(provider.name) →", destination: url)
                    }
                }
            }

            Section {
                ForEach(provider.models) { model in
                    Text(model.displayName)
                }
                .onDelete { indices in
                    provider.models.remove(atOffsets: indices)
                    providerStore.update(provider)
                }
                HStack {
                    TextField("Add model ID", text: $newModelID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Add") {
                        let trimmed = newModelID.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        provider.models.append(AIModel(id: trimmed, displayName: trimmed))
                        providerStore.update(provider)
                        newModelID = ""
                    }
                    .disabled(newModelID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Models")
            }

            Section {
                Button("Remove Provider", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Remove \(provider.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                providerStore.remove(provider)
                dismiss()
            }
        } message: {
            Text("Its API key will be deleted from the Keychain. Existing chats using this model will keep their history but can no longer generate new replies.")
        }
    }
}

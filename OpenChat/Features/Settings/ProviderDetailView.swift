import SwiftUI

struct ProviderDetailView: View {
    @State var provider: ConfiguredProvider

    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var showingAddNewKeyDialog = false
    @State private var showingRemoveKeyConfirmation = false
    @State private var newModelID: String = ""
    @State private var showingDeleteConfirmation = false

    private var storedRedactedAPIKey: String? {
        providerStore.redactedAPIKey(for: provider)
    }

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
                APIKeySettingsSection(
                    placeholder: "Add API key",
                    redactedKey: storedRedactedAPIKey,
                    draftKey: $apiKey,
                    helpURL: provider.template?.keyHelpURL,
                    helpProviderName: provider.name,
                    onSave: saveAPIKey,
                    onRequestReplace: {
                        apiKey = ""
                        showingAddNewKeyDialog = true
                    },
                    onRequestRemove: {
                        showingRemoveKeyConfirmation = true
                    }
                )
            }

            Section {
                ForEach(provider.models) { model in
                    HStack {
                        Text(model.displayName)
                        Spacer()
                        ModelCapabilitySigns(capabilities: model.capabilities)
                    }
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
        .overlay {
            if showingAddNewKeyDialog {
                APIKeyReplaceDialog(
                    title: "Add New Key",
                    placeholder: "API key",
                    draftKey: $apiKey,
                    onCancel: dismissAddNewKeyDialog,
                    onSave: {
                        saveAPIKey()
                        dismissAddNewKeyDialog()
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(Theme.springFast, value: showingAddNewKeyDialog)
        .confirmationDialog(
            "Remove \(provider.name) key?",
            isPresented: $showingRemoveKeyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Key", role: .destructive) {
                providerStore.removeAPIKey(for: provider)
                apiKey = ""
                Haptics.light()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This provider won’t be usable until you add a key again.")
        }
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

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        providerStore.setAPIKey(trimmed, for: provider)
        apiKey = ""
        Haptics.success()
    }

    private func dismissAddNewKeyDialog() {
        showingAddNewKeyDialog = false
        apiKey = ""
    }
}

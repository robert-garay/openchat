import SwiftUI

struct ProviderDetailView: View {
    @State var provider: ConfiguredProvider

    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var showingAddNewKeyDialog = false
    @State private var showingRemoveKeyConfirmation = false
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

            if provider.requiresAPIKey {
                APIKeySettingsSection(
                    placeholder: "Add API key",
                    redactedKey: storedRedactedAPIKey,
                    draftKey: $apiKey,
                    helpURL: provider.template?.keyHelpURL,
                    helpProviderName: provider.name,
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
                Button("Remove Provider", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if provider.requiresAPIKey, storedRedactedAPIKey == nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAPIKey() }
                        .fontWeight(.semibold)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .overlay {
            if showingAddNewKeyDialog {
                APIKeyReplaceDialog(
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
            } else if showingRemoveKeyConfirmation {
                SettingsConfirmDialog(
                    title: "Remove \(provider.name) key?",
                    message: "This provider won’t be usable until you add a key again.",
                    confirmTitle: "Remove Key",
                    onCancel: { showingRemoveKeyConfirmation = false },
                    onConfirm: {
                        providerStore.removeAPIKey(for: provider)
                        apiKey = ""
                        showingRemoveKeyConfirmation = false
                        Haptics.light()
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            } else if showingDeleteConfirmation {
                SettingsConfirmDialog(
                    title: "Remove \(provider.name)?",
                    message: "Its API key will be deleted from the Keychain. Existing chats using this model will keep their history but can no longer generate new replies.",
                    confirmTitle: "Remove",
                    onCancel: { showingDeleteConfirmation = false },
                    onConfirm: {
                        providerStore.remove(provider)
                        dismiss()
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(Theme.springFast, value: showingAddNewKeyDialog)
        .animation(Theme.springFast, value: showingRemoveKeyConfirmation)
        .animation(Theme.springFast, value: showingDeleteConfirmation)
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

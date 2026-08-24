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

            if providerStore.supportsBalance(for: provider) {
                balanceSection
            }

            if provider.templateID == nil {
                Section {
                    logoPicker
                } header: {
                    Text("Logo")
                } footer: {
                    Text("Pick a brand mark if this endpoint is a known host. Otherwise a generic server icon is used.")
                }
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
                    message: "Its API key will be deleted from the Keychain. "
                             + "Existing chats using this model will keep their history but can no longer generate new replies.",
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
        .onAppear {
            providerStore.refreshBalanceIfNeeded(for: provider)
        }
    }

    private var logoPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                CustomEndpointLogoButton(
                    logoAssetName: nil,
                    symbolName: "server.rack",
                    name: "Default",
                    isSelected: provider.customLogoID == nil
                ) {
                    provider.customLogoID = nil
                    providerStore.update(provider)
                }
                ForEach(CustomEndpointLogoOption.all) { option in
                    CustomEndpointLogoButton(
                        logoAssetName: option.logoAssetName,
                        symbolName: "server.rack",
                        name: option.name,
                        isSelected: provider.customLogoID == option.id
                    ) {
                        provider.customLogoID = option.id
                        providerStore.update(provider)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var balanceSection: some View {
        let balance = providerStore.balance(for: provider)
        let error = providerStore.balanceError(for: provider)
        let isLoading = providerStore.isLoadingBalance(for: provider)

        Section {
            HStack {
                Text("Credit Balance")
                    .foregroundStyle(.primary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let balance {
                    Text(formattedBalance(balance))
                        .font(.body.monospaced())
                        .foregroundStyle(balanceColor(for: balance))
                } else if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Account")
        } footer: {
            if error != nil {
                Text("Tap to retry")
                    .foregroundStyle(.secondary)
            }
        }
        .onTapGesture {
            providerStore.refreshBalanceIfNeeded(for: provider, force: true)
        }
    }

    private func formattedBalance(_ balance: ProviderBalanceClient.Balance) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = balance.currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance.total)) ?? "\(balance.total) \(balance.currency)"
    }

    private func balanceColor(for balance: ProviderBalanceClient.Balance) -> Color {
        guard let isSufficient = balance.isSufficient else { return .primary }
        return isSufficient ? .primary : .orange
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        providerStore.setAPIKey(trimmed, for: provider)
        apiKey = ""
        Haptics.success()
        providerStore.refreshBalanceIfNeeded(for: provider, force: true)
    }

    private func dismissAddNewKeyDialog() {
        showingAddNewKeyDialog = false
        apiKey = ""
    }
}

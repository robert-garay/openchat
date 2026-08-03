import SwiftUI

struct ProviderDetailView: View {
    @State var provider: ConfiguredProvider

    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var showingAddNewKeyDialog = false
    @State private var newModelID: String = ""
    @State private var showingDeleteConfirmation = false
    @FocusState private var newKeyFieldFocused: Bool

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
                Section {
                    if let redacted = storedRedactedAPIKey {
                        ZStack(alignment: .leading) {
                            TextField("API Key", text: .constant(redacted))
                                .font(.body.monospaced())
                                .disabled(true)
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    apiKey = ""
                                    showingAddNewKeyDialog = true
                                }
                        }
                    } else {
                        SecureField("Add API key", text: $apiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button("Save Key") {
                            saveAPIKey()
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
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
                addNewKeyDialog
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(Theme.springFast, value: showingAddNewKeyDialog)
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

    private var addNewKeyDialog: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { dismissAddNewKeyDialog() }

            VStack(spacing: 16) {
                Text("Add New Key")
                    .font(.headline)

                SecureField("API key", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(12)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                    .focused($newKeyFieldFocused)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismissAddNewKeyDialog()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button("Save") {
                        saveAPIKey()
                        dismissAddNewKeyDialog()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            .padding(.horizontal, 24)
        }
        .onAppear { newKeyFieldFocused = true }
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
        newKeyFieldFocused = false
    }
}

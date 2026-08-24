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
    @State private var selectedLogoID: String?

    @State private var isTestingConnection = false
    @State private var connectionStatus: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedURL: String {
        baseURL.trimmingCharacters(in: .whitespaces)
    }

    private var normalizedURL: String {
        var url = trimmedURL
        while url.hasSuffix("/") {
            url.removeLast()
        }
        return url
    }

    private var models: [AIModel] {
        var seen = Set<String>()
        return modelsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .map { AIModel(id: $0, displayName: $0) }
    }

    // MARK: - Validation

    private var nameError: String? {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > 40 {
            return "Name must be 40 characters or fewer."
        }
        let duplicate = providerStore.providers.contains {
            $0.name.trimmingCharacters(in: .whitespaces)
                .localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
        let templateDuplicate = ProviderTemplate.all.contains {
            $0.name.trimmingCharacters(in: .whitespaces)
                .localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
        if duplicate || templateDuplicate {
            return "A provider with this name already exists."
        }
        return nil
    }

    private var urlError: String? {
        let trimmed = trimmedURL
        let urlValue = normalizedURL
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed) else {
            return "Enter a valid URL."
        }
        guard let scheme = url.scheme, scheme == "http" || scheme == "https" else {
            return "URL must start with http:// or https://."
        }
        guard let host = url.host(), !host.isEmpty else {
            return "Enter a valid host, e.g. api.example.com."
        }
        let duplicate = providerStore.providers.contains {
            var existing = $0.baseURL.trimmingCharacters(in: .whitespaces)
            while existing.hasSuffix("/") {
                existing.removeLast()
            }
            return existing.localizedCaseInsensitiveCompare(urlValue) == .orderedSame
        }
        if duplicate {
            return "This endpoint is already configured."
        }
        return nil
    }

    private var modelsError: String? {
        guard !modelsText.isEmpty else { return nil }
        guard !models.isEmpty else {
            return "Enter at least one valid model ID."
        }
        return nil
    }

    private var apiKeyError: String? {
        guard requiresAPIKey else { return nil }
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return nil
    }

    private var apiKeyPlaceholder: String {
        let lowered = baseURL.lowercased()
        if lowered.contains("openrouter") { return "sk-or-..." }
        if lowered.contains("anthropic") { return "sk-ant-..." }
        return "sk-..."
    }

    private var canSave: Bool {
        !trimmedName.isEmpty &&
        nameError == nil &&
        !normalizedURL.isEmpty &&
        urlError == nil &&
        !models.isEmpty &&
        modelsError == nil &&
        (!requiresAPIKey || !apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var canTestConnection: Bool {
        !isTestingConnection &&
        !normalizedURL.isEmpty &&
        urlError == nil &&
        (!requiresAPIKey || !apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        Form {
            Section("Endpoint") {
                TextField("Name (e.g. My Ollama Server)", text: $name)
                    .onSubmit { name = name.trimmingCharacters(in: .whitespaces) }
                if let nameError {
                    Text(nameError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Name error: \(nameError)")
                }

                TextField("Base URL", text: $baseURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        var cleaned = baseURL.trimmingCharacters(in: .whitespaces)
                        while cleaned.hasSuffix("/") {
                            cleaned.removeLast()
                        }
                        baseURL = cleaned
                    }
                if let urlError {
                    Text(urlError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("URL error: \(urlError)")
                }
            }

            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text(isTestingConnection ? "Testing…" : "Test & Fetch Models")
                        if isTestingConnection {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!canTestConnection)

                if let connectionStatus {
                    Text(connectionStatus)
                        .font(.caption)
                        .foregroundStyle(connectionStatusColor)
                        .accessibilityLabel("Connection status: \(connectionStatus)")
                }
            } header: {
                Text("Discovery")
            } footer: {
                Text("Tries to reach the endpoint and populate the model list automatically.")
            }

            Section {
                TextField("model-a, model-b, model-c", text: $modelsText, axis: .vertical)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if let modelsError {
                    Text(modelsError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Models error: \(modelsError)")
                }
            } header: {
                Text("Model IDs")
            } footer: {
                Text("Comma-separated model IDs exactly as the endpoint expects them, e.g. \"llama3.1, qwen2.5:14b\".")
            }

            Section {
                Toggle("Requires API Key", isOn: $requiresAPIKey.animation())
                if requiresAPIKey {
                    SecureField(apiKeyPlaceholder, text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if let apiKeyError {
                        Text(apiKeyError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel("API key error: \(apiKeyError)")
                    }
                }
            }

            Section {
                logoPicker
            } header: {
                Text("Logo")
            } footer: {
                Text("Pick a brand mark if this endpoint is a known host. Otherwise a generic server icon is used.")
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

    private var logoPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                CustomEndpointLogoButton(
                    logoAssetName: nil,
                    symbolName: "server.rack",
                    name: "Default",
                    isSelected: selectedLogoID == nil
                ) {
                    selectedLogoID = nil
                }
                ForEach(CustomEndpointLogoOption.all) { option in
                    CustomEndpointLogoButton(
                        logoAssetName: option.logoAssetName,
                        symbolName: "server.rack",
                        name: option.name,
                        isSelected: selectedLogoID == option.id
                    ) {
                        selectedLogoID = option.id
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var connectionStatusColor: Color {
        guard let connectionStatus else { return .primary }
        return connectionStatus.hasPrefix("Connected") ? .green : .red
    }

    private func testConnection() {
        isTestingConnection = true
        connectionStatus = nil
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        let tempProvider = ConfiguredProvider.customEndpoint(
            name: trimmedName.isEmpty ? "Test" : trimmedName,
            baseURL: normalizedURL,
            models: [],
            requiresAPIKey: requiresAPIKey
        )
        Task {
            do {
                let client = ProviderModelsClient()
                let fetched = try await client.fetchModels(
                    for: tempProvider,
                    apiKey: requiresAPIKey ? trimmedKey : nil
                )
                await MainActor.run {
                    modelsText = fetched.map(\.id).joined(separator: ", ")
                    connectionStatus = "Connected — found \(fetched.count) model\(fetched.count == 1 ? "" : "s")."
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = "Couldn’t connect: \(error.localizedDescription)"
                    isTestingConnection = false
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let added = providerStore.addCustom(
            name: trimmedName,
            baseURL: normalizedURL,
            models: models,
            requiresAPIKey: requiresAPIKey,
            logoID: selectedLogoID
        )
        if requiresAPIKey, let added {
            providerStore.setAPIKey(apiKey.trimmingCharacters(in: .whitespaces), for: added)
        }
        Haptics.success()
        onSaved()
    }
}

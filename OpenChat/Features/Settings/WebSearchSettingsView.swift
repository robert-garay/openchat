import SwiftUI

struct WebSearchSettingsView: View {
    @Environment(WebSearchStore.self) private var webSearchStore

    var body: some View {
        List {
            Section {
                Label {
                    Text("Add one or more search API keys. Only the active provider is used per chat. Models with tool calling decide when to search; others get results injected automatically. No crawl/extract providers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "globe")
                        .foregroundStyle(Color.accentColor)
                }
            }

            Section {
                Toggle("Enable Web Search", isOn: Binding(
                    get: { webSearchStore.isEnabled },
                    set: { webSearchStore.setEnabled($0) }
                ))
                .disabled(!webSearchStore.hasAnyAPIKey)
            } footer: {
                Text(masterFooter)
            }

            Section {
                ForEach(WebSearchProviderKind.allCases) { kind in
                    NavigationLink {
                        WebSearchProviderDetailView(kind: kind)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: kind.symbolName)
                                .font(.body)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.displayName)
                                Text(statusSubtitle(for: kind))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            if webSearchStore.hasAPIKey(for: kind),
                               webSearchStore.activeProvider == kind {
                                Text("Active")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("Saving a key on a provider can make it active. Switch Active from a provider’s detail screen.")
            }
        }
        .navigationTitle("Web Search")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var masterFooter: String {
        if !webSearchStore.hasAnyAPIKey {
            return "Save a search API key to turn web search on."
        }
        if webSearchStore.isActive {
            return "Active provider: \(webSearchStore.activeProviderDisplayName). You can also turn search off per chat with the globe button."
        }
        if webSearchStore.isEnabled {
            return "Enabled, but the active provider needs an API key."
        }
        return "Keys saved, but web search is turned off globally."
    }

    private func statusSubtitle(for kind: WebSearchProviderKind) -> String {
        if webSearchStore.hasAPIKey(for: kind) {
            return webSearchStore.redactedAPIKey(for: kind) ?? "Key saved"
        }
        return kind.subtitle
    }
}

struct WebSearchProviderDetailView: View {
    let kind: WebSearchProviderKind

    @Environment(WebSearchStore.self) private var webSearchStore
    @State private var apiKey: String = ""
    @State private var showingReplaceKey = false
    @State private var showingRemoveConfirmation = false
    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        List {
            Section {
                LabeledContent("Provider", value: kind.displayName)
                Text(kind.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if webSearchStore.hasAPIKey(for: kind) {
                Section {
                    Button {
                        webSearchStore.setActiveProvider(kind)
                        webSearchStore.setEnabled(true)
                        Haptics.light()
                    } label: {
                        HStack {
                            Label("Use as Active Provider", systemImage: "checkmark.circle")
                            Spacer()
                            if webSearchStore.activeProvider == kind {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .disabled(webSearchStore.activeProvider == kind)
                } footer: {
                    Text("Only the active provider is called when web search runs.")
                }
            }

            Section {
                if let redacted = webSearchStore.redactedAPIKey(for: kind) {
                    ZStack(alignment: .leading) {
                        TextField("API Key", text: .constant(redacted))
                            .font(.body.monospaced())
                            .disabled(true)
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                apiKey = ""
                                showingReplaceKey = true
                            }
                    }
                    Button("Remove Key", role: .destructive) {
                        showingRemoveConfirmation = true
                    }
                } else {
                    SecureField(kind.apiKeyPlaceholder, text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($keyFieldFocused)
                    Button("Save Key") {
                        saveKey()
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("API Key")
            } footer: {
                if let url = kind.keyHelpURL {
                    Link("Get an API key from \(kind.displayName) →", destination: url)
                }
            }
        }
        .navigationTitle(kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if showingReplaceKey {
                replaceKeyDialog
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(Theme.springFast, value: showingReplaceKey)
        .confirmationDialog("Remove \(kind.displayName) key?", isPresented: $showingRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove Key", role: .destructive) {
                webSearchStore.removeAPIKey(for: kind)
                Haptics.light()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This provider won’t be usable until you add a key again.")
        }
        .onAppear {
            if !webSearchStore.hasAPIKey(for: kind) {
                keyFieldFocused = true
            }
        }
    }

    private var replaceKeyDialog: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { dismissReplaceKey() }

            VStack(spacing: 16) {
                Text("Replace \(kind.displayName) Key")
                    .font(.headline)

                SecureField(kind.apiKeyPlaceholder, text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(12)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                    .focused($keyFieldFocused)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismissReplaceKey()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button("Save") {
                        saveKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            .padding(.horizontal, 24)
        }
        .onAppear { keyFieldFocused = true }
    }

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        webSearchStore.setAPIKey(trimmed, for: kind)
        apiKey = ""
        showingReplaceKey = false
        keyFieldFocused = false
        Haptics.success()
    }

    private func dismissReplaceKey() {
        showingReplaceKey = false
        apiKey = ""
        keyFieldFocused = false
    }
}

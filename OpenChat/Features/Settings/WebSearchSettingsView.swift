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
                            ProviderLogoView(
                                logoAssetName: kind.logoAssetName,
                                symbolName: kind.symbolName,
                                tint: Color(hex: kind.tintHex),
                                size: 30
                            )

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

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    ProviderLogoView(
                        logoAssetName: kind.logoAssetName,
                        symbolName: kind.symbolName,
                        tint: Color(hex: kind.tintHex),
                        size: 44,
                        cornerRadius: 12
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind.displayName)
                            .font(.headline)
                        Text(kind.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
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

            APIKeySettingsSection(
                placeholder: kind.apiKeyPlaceholder,
                redactedKey: webSearchStore.redactedAPIKey(for: kind),
                draftKey: $apiKey,
                helpURL: kind.keyHelpURL,
                helpProviderName: kind.displayName,
                onSave: saveKey,
                onRequestReplace: {
                    apiKey = ""
                    showingReplaceKey = true
                },
                onRequestRemove: {
                    showingRemoveConfirmation = true
                }
            )
        }
        .navigationTitle(kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if showingReplaceKey {
                APIKeyReplaceDialog(
                    title: "Replace \(kind.displayName) Key",
                    placeholder: kind.apiKeyPlaceholder,
                    draftKey: $apiKey,
                    onCancel: dismissReplaceKey,
                    onSave: saveKey
                )
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
    }

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        webSearchStore.setAPIKey(trimmed, for: kind)
        apiKey = ""
        showingReplaceKey = false
        Haptics.success()
    }

    private func dismissReplaceKey() {
        showingReplaceKey = false
        apiKey = ""
    }
}

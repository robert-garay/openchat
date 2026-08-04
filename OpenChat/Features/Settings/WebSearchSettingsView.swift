import SwiftUI

struct WebSearchSettingsView: View {
    @Environment(WebSearchStore.self) private var webSearchStore

    var body: some View {
        List {
            Section {
                Label {
                    Text("Add search API keys here. Pick which provider to use from the web search button in chat. Models with tool calling decide when to search; others get results injected automatically.")
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
                        }
                    }
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("Registered providers appear in the chat web search menu.")
            }
        }
        .navigationTitle("Web Search")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var masterFooter: String {
        if !webSearchStore.hasAnyAPIKey {
            return "Save a search API key, then choose a provider from the chat web search button."
        }
        if webSearchStore.isActive {
            return "Using \(webSearchStore.activeProviderDisplayName). Change providers from the chat web search button."
        }
        if webSearchStore.isEnabled {
            return "Enabled, but no usable provider key is selected. Pick one in chat after saving a key."
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
                    placeholder: kind.apiKeyPlaceholder,
                    draftKey: $apiKey,
                    onCancel: dismissReplaceKey,
                    onSave: saveKey
                )
                .transition(.opacity)
                .zIndex(1)
            } else if showingRemoveConfirmation {
                SettingsConfirmDialog(
                    title: "Remove \(kind.displayName) key?",
                    message: "This provider won’t be usable until you add a key again.",
                    confirmTitle: "Remove Key",
                    onCancel: { showingRemoveConfirmation = false },
                    onConfirm: {
                        webSearchStore.removeAPIKey(for: kind)
                        showingRemoveConfirmation = false
                        Haptics.light()
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(Theme.springFast, value: showingReplaceKey)
        .animation(Theme.springFast, value: showingRemoveConfirmation)
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

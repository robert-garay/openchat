import SwiftUI

struct WebSearchSettingsView: View {
    @Environment(WebSearchStore.self) private var webSearchStore
    @State private var apiKey: String = ""
    @State private var showingReplaceKey = false
    @State private var showingRemoveConfirmation = false
    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        List {
            Section {
                Label {
                    Text("Add a Tavily API key to give every chat model live web search. Models with tool calling decide when to search; others get search results injected automatically.")
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
                .disabled(!webSearchStore.hasAPIKey)
            } footer: {
                if webSearchStore.hasAPIKey {
                    Text(modeFooter)
                } else {
                    Text("Save a Tavily key to turn web search on.")
                }
            }

            Section {
                if let redacted = webSearchStore.redactedAPIKey() {
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
                    SecureField("tvly-…", text: $apiKey)
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
                Text("Tavily API Key")
            } footer: {
                Link("Get a free API key from Tavily →", destination: URL(string: "https://app.tavily.com/home")!)
            }
        }
        .navigationTitle("Web Search")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if showingReplaceKey {
                replaceKeyDialog
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(Theme.springFast, value: showingReplaceKey)
        .confirmationDialog("Remove Tavily key?", isPresented: $showingRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove Key", role: .destructive) {
                webSearchStore.removeAPIKey()
                Haptics.light()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Web search will stop until you add a key again.")
        }
        .onAppear {
            if !webSearchStore.hasAPIKey {
                keyFieldFocused = true
            }
        }
    }

    private var modeFooter: String {
        if webSearchStore.isActive {
            return "Active. Tool-capable models use native tool calling; all other models fall back to injected search results."
        }
        return "Key saved, but web search is turned off."
    }

    private var replaceKeyDialog: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { dismissReplaceKey() }

            VStack(spacing: 16) {
                Text("Replace Tavily Key")
                    .font(.headline)

                SecureField("New Tavily key", text: $apiKey)
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
        webSearchStore.setAPIKey(trimmed)
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

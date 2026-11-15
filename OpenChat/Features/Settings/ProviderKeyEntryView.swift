import SwiftUI

struct ProviderKeyEntryView: View {
    let template: ProviderTemplate
    var onSaved: () -> Void

    @Environment(ProviderStore.self) private var providerStore
    @State private var apiKey: String = ""
    @State private var headerEntries: [CustomHeaderEntry]
    @FocusState private var fieldFocused: Bool

    init(template: ProviderTemplate, onSaved: @escaping () -> Void) {
        self.template = template
        self.onSaved = onSaved
        _headerEntries = State(initialValue: CustomHeaderEntry.list(from: template.defaultHeaders))
    }

    var body: some View {
        Form {
            Section {
                Text("Your API key is stored securely in the iOS Keychain and never leaves your device except to call \(template.name) directly.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
            }

            Section {
                SecureField(template.apiKeyPlaceholder, text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($fieldFocused)
            } header: {
                Text("API Key")
            } footer: {
                if let url = template.keyHelpURL {
                    Link("Get an API key from \(template.name) →", destination: url)
                }
            }

            if let usageNote = template.usageNote {
                Section {
                    Text(usageNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }

            CustomHeadersEditor(
                headers: $headerEntries,
                startsExpanded: !template.defaultHeaders.isEmpty
            )
        }
        .providerToolbarTitle(
            template.name,
            logoAssetName: template.logoAssetName,
            symbolName: template.symbolName,
            tint: Color(hex: template.tint)
        )
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { fieldFocused = true }
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let provider = providerStore.addFromTemplate(
            template,
            customHeaders: headerEntries.headerDictionary
        ) else { return }
        providerStore.setAPIKey(trimmed, for: provider)
        Haptics.success()
        onSaved()
    }
}

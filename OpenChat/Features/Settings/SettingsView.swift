import SwiftUI

struct SettingsView: View {
    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("com.openchat.appearance") private var appearance: AppAppearance = .system
    @State private var showingAddProvider = false

    var body: some View {
        NavigationStack {
            List {
                Section("Models") {
                    if providerStore.providers.isEmpty {
                        Text("No providers connected yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(providerStore.providers) { provider in
                        NavigationLink {
                            ProviderDetailView(provider: provider)
                        } label: {
                            HStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(hex: provider.tint).opacity(0.15))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: provider.symbolName)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Color(hex: provider.tint))
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.name)
                                    if !providerStore.hasUsableCredentials(provider) {
                                        Text("Needs an API key")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                if !provider.isEnabled {
                                    Text("Off")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Button {
                        showingAddProvider = true
                    } label: {
                        Label("Add a Model", systemImage: "plus.circle.fill")
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Label(option.label, systemImage: option.symbolName).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    Link(destination: URL(string: "https://github.com/robert-garay/openchat")!) {
                        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("OpenChat connects directly to the providers you configure. Your conversations are stored only on this device.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddProvider) {
                AddProviderView()
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

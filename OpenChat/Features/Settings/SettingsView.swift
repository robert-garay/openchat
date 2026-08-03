import SwiftUI

struct SettingsView: View {
    @Environment(ProviderStore.self) private var providerStore
    @Environment(AgentDataSourceStore.self) private var dataSourceStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("com.openchat.appearance") private var appearance: AppAppearance = .system
    @State private var showingAddProvider = false

    var body: some View {
        NavigationStack {
            List {
                Section("Providers") {
                    if providerStore.providers.isEmpty {
                        Text("No providers connected yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(providerStore.providers) { provider in
                        NavigationLink {
                            ProviderDetailView(provider: provider)
                        } label: {
                            HStack {
                                ProviderLogoView(
                                    logoAssetName: provider.logoAssetName,
                                    symbolName: provider.symbolName,
                                    tint: Color(hex: provider.tint),
                                    size: 30
                                )
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
                    NavigationLink {
                        DataSourcesSettingsView()
                    } label: {
                        HStack {
                            Label("Agent Data Sources", systemImage: "sensor.tag.radiowaves.forward")
                            Spacer()
                            Text(dataSourcesSummary)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Enabled calendar and fitness data are included with chat requests. All sources are off by default.")
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

    private var dataSourcesSummary: String {
        let count = dataSourceStore.enabledCount
        if count == 0 { return "Off" }
        return "\(count) on"
    }
}

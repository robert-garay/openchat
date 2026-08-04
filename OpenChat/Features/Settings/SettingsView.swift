import SwiftUI

struct SettingsView: View {
    @Environment(ProviderStore.self) private var providerStore
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
                                Text(provider.name)
                            }
                        }
                    }
                    Button {
                        showingAddProvider = true
                    } label: {
                        Label("Add a Provider", systemImage: "plus.circle.fill")
                    }
                }

                Section("Tools") {
                    NavigationLink {
                        WebSearchSettingsView()
                    } label: {
                        Label("Web Search", systemImage: "globe")
                    }
                    NavigationLink {
                        SkillsSettingsView()
                    } label: {
                        Label("Skills", systemImage: "bolt.fill")
                    }
                }

                Section("Privacy") {
                    NavigationLink {
                        DataSourcesSettingsView()
                    } label: {
                        Label("Agent Data Sources", systemImage: "sensor.tag.radiowaves.forward")
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
                    .preferredColorScheme(appearance.colorScheme)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

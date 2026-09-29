import SwiftUI

/// First-run flow: optional on-device download, then optional cloud providers.
struct FirstLaunchOnboardingView: View {
    @Environment(ProviderStore.self) private var providerStore
    @Environment(LocalModelStore.self) private var localModelStore

    @AppStorage(OnboardingSetup.completedKey) private var setupCompleted = false
    @State private var phase: Phase = .local
    @State private var showingAddProvider = false

    private enum Phase {
        case local
        case cloud
    }

    private var hasLocalModel: Bool {
        !localModelStore.readyEntries.isEmpty
    }

    private var hasCloudProvider: Bool {
        providerStore.providers.contains { $0.id != OnDeviceProvider.providerID }
    }

    private var canFinish: Bool {
        hasLocalModel || hasCloudProvider
    }

    var body: some View {
        Group {
            switch phase {
            case .local:
                LocalModelsOnboardingView(flow: .firstLaunch, onFirstLaunchAdvance: {
                    phase = .cloud
                })
            case .cloud:
                cloudSetupStep
            }
        }
    }

    private var cloudSetupStep: some View {
        NavigationStack {
            List {
                Section {
                    if hasLocalModel {
                        Label("On-device model ready — no API key needed to start chatting.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        Text("Add an API key for OpenAI, Claude, Gemini, OpenRouter, or a custom endpoint. You can always add more later in Settings.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        showingAddProvider = true
                    } label: {
                        Label("Add a cloud provider", systemImage: "key.fill")
                            .font(.headline)
                    }
                    if hasCloudProvider {
                        Label("Provider connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    Button {
                        finishSetup()
                    } label: {
                        Text(hasLocalModel ? "Get started" : "Get started with cloud")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canFinish)
                } footer: {
                    if !canFinish {
                        Text("Install an on-device model or connect a cloud provider to continue.")
                    } else if hasLocalModel && !hasCloudProvider {
                        Text("You can add cloud providers anytime from Settings.")
                    }
                }
            }
            .navigationTitle("Cloud providers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phase == .cloud, !hasLocalModel {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { phase = .local }
                    }
                }
            }
            .sheet(isPresented: $showingAddProvider) {
                AddProviderView(dismissesOnSave: false)
            }
        }
    }

    private func finishSetup() {
        guard canFinish else { return }
        Haptics.light()
        setupCompleted = true
    }
}

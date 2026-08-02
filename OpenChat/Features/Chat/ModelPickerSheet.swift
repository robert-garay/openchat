import SwiftUI

struct ModelPickerSheet: View {
    let currentProviderID: String
    let currentModelID: String
    let onSelect: (String, String) -> Void

    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var openRouterProvider: ConfiguredProvider? {
        providerStore.enabledProviders.first { $0.id == "openrouter" }
    }

    private var otherProviders: [ConfiguredProvider] {
        providerStore.enabledProviders.filter { $0.id != "openrouter" }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var openRouterSearchResults: [OpenRouterCatalogModel] {
        OpenRouterModelCatalog.filtered(models: providerStore.openRouterModels, query: searchText)
    }

    private var topFreeModels: [OpenRouterCatalogModel] {
        OpenRouterModelCatalog.topFree(from: providerStore.openRouterModels)
    }

    private var topOpenSourceModels: [OpenRouterCatalogModel] {
        OpenRouterModelCatalog.topOpenSource(from: providerStore.openRouterModels)
    }

    var body: some View {
        NavigationStack {
            List {
                if let openRouterProvider {
                    openRouterSections(provider: openRouterProvider)
                }

                ForEach(otherProviders) { provider in
                    Section {
                        ForEach(filteredModels(for: provider)) { model in
                            modelButton(providerID: provider.id, model: model)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            ProviderLogoView(
                                logoAssetName: provider.logoAssetName,
                                symbolName: provider.symbolName,
                                tint: Color(hex: provider.tint),
                                size: 20,
                                cornerRadius: 5
                            )
                            Text(provider.name)
                        }
                        .foregroundStyle(Color(hex: provider.tint))
                        .textCase(nil)
                    }
                }
            }
            .searchable(text: $searchText, prompt: openRouterProvider == nil ? "Search models" : "Search OpenRouter models")
            .navigationTitle("Choose a Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if openRouterProvider != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            providerStore.refreshOpenRouterModelsIfNeeded(force: true)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh OpenRouter models")
                        .disabled(providerStore.isLoadingOpenRouterModels)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            providerStore.refreshOpenRouterModelsIfNeeded()
        }
    }

    @ViewBuilder
    private func openRouterSections(provider: ConfiguredProvider) -> some View {
        if providerStore.isLoadingOpenRouterModels && providerStore.openRouterModels.isEmpty {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading OpenRouter models…")
                        .foregroundStyle(.secondary)
                }
            } header: {
                openRouterHeader(provider)
            }
        } else if let error = providerStore.openRouterModelsError, providerStore.openRouterModels.isEmpty {
            Section {
                Text(error)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    providerStore.refreshOpenRouterModelsIfNeeded(force: true)
                }
            } header: {
                openRouterHeader(provider)
            }
        } else if isSearching {
            Section {
                if openRouterSearchResults.isEmpty {
                    Text("No models match “\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))”.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(openRouterSearchResults) { model in
                        openRouterModelButton(model)
                    }
                }
            } header: {
                openRouterHeader(provider)
            } footer: {
                Text("\(openRouterSearchResults.count) models")
            }
        } else {
            Section {
                ForEach(topFreeModels) { model in
                    openRouterModelButton(model)
                }
                if topFreeModels.isEmpty {
                    Text("No free models available right now.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Top Free", systemImage: "gift")
            } footer: {
                Text("Search to browse the full OpenRouter catalog.")
            }

            Section {
                ForEach(topOpenSourceModels) { model in
                    openRouterModelButton(model)
                }
                if topOpenSourceModels.isEmpty {
                    Text("No open-source models available right now.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Top Open Source", systemImage: "chevron.left.forwardslash.chevron.right")
            }

            savedModelsSection(provider: provider, excluding: topFreeModels + topOpenSourceModels)
        }
    }

    @ViewBuilder
    private func savedModelsSection(
        provider: ConfiguredProvider,
        excluding highlighted: [OpenRouterCatalogModel]
    ) -> some View {
        let saved = provider.models.filter { model in
            !highlighted.contains { $0.id == model.id }
        }
        if !saved.isEmpty {
            Section {
                ForEach(saved) { model in
                    modelButton(providerID: provider.id, model: model)
                }
            } header: {
                Label("Saved", systemImage: provider.symbolName)
                    .foregroundStyle(Color(hex: provider.tint))
            }
        }
    }

    private func openRouterHeader(_ provider: ConfiguredProvider) -> some View {
        Label(provider.name, systemImage: provider.symbolName)
            .foregroundStyle(Color(hex: provider.tint))
    }

    private func filteredModels(for provider: ConfiguredProvider) -> [AIModel] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return provider.models }
        return provider.models.filter {
            $0.id.localizedCaseInsensitiveContains(trimmed) ||
            $0.displayName.localizedCaseInsensitiveContains(trimmed) ||
            ($0.subtitle?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private func openRouterModelButton(_ model: OpenRouterCatalogModel) -> some View {
        Button {
            Haptics.light()
            providerStore.rememberOpenRouterModel(model)
            onSelect("openrouter", model.id)
            dismiss()
        } label: {
            modelRow(
                title: model.displayName,
                subtitle: model.subtitle,
                isSelected: currentProviderID == "openrouter" && currentModelID == model.id
            )
        }
    }

    private func modelButton(providerID: String, model: AIModel) -> some View {
        Button {
            Haptics.light()
            onSelect(providerID, model.id)
            dismiss()
        } label: {
            modelRow(
                title: model.displayName,
                subtitle: model.subtitle,
                isSelected: providerID == currentProviderID && model.id == currentModelID
            )
        }
    }

    private func modelRow(title: String, subtitle: String?, isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            }
        }
    }
}

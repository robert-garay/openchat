import SwiftUI

struct ModelPickerSheet: View {
    let currentProviderID: String
    let currentModelID: String
    let onSelect: (String, String) -> Void

    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCapabilities: Set<ModelCapability> = []

    private var openRouterProvider: ConfiguredProvider? {
        providerStore.enabledProviders.first { $0.id == "openrouter" }
    }

    private var otherProviders: [ConfiguredProvider] {
        providerStore.enabledProviders.filter { $0.id != "openrouter" }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Active when the user is text-searching, filtering by capability, or both.
    private var isFiltering: Bool {
        isSearching || !selectedCapabilities.isEmpty
    }

    private var openRouterSearchResults: [OpenRouterCatalogModel] {
        OpenRouterModelCatalog.filtered(
            models: providerStore.openRouterModels,
            query: searchText,
            capabilities: selectedCapabilities
        )
    }

    private var topOpenSourceModels: [OpenRouterCatalogModel] {
        OpenRouterModelCatalog.topOpenSource(from: providerStore.openRouterModels)
    }

    private var emptyFilterMessage: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return "No models match “\(trimmed)”."
        }
        return "No models match the selected capabilities."
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
            .safeAreaInset(edge: .bottom) {
                ModelCapabilityLegend(selectedCapabilities: $selectedCapabilities)
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
        } else if isFiltering {
            Section {
                if openRouterSearchResults.isEmpty {
                    Text(emptyFilterMessage)
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
                ForEach(topOpenSourceModels) { model in
                    openRouterModelButton(model)
                }
                if topOpenSourceModels.isEmpty {
                    Text("No open-source models available right now.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Top Open Source", systemImage: "chevron.left.forwardslash.chevron.right")
            } footer: {
                Text("Search or filter by capability to browse the full OpenRouter catalog.")
            }

            savedModelsSection(provider: provider, excluding: topOpenSourceModels)
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
        return provider.models.filter { model in
            let matchesText = trimmed.isEmpty
                || model.id.localizedCaseInsensitiveContains(trimmed)
                || model.displayName.localizedCaseInsensitiveContains(trimmed)
                || (model.subtitle?.localizedCaseInsensitiveContains(trimmed) ?? false)
            let matchesCapabilities = ModelCapability.matches(model.capabilities, filters: selectedCapabilities)
            return matchesText && matchesCapabilities
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
                capabilities: model.capabilities,
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
                capabilities: model.capabilities,
                isSelected: providerID == currentProviderID && model.id == currentModelID
            )
        }
    }

    private func modelRow(
        title: String,
        subtitle: String?,
        capabilities: [ModelCapability],
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            ModelCapabilitySigns(capabilities: capabilities)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

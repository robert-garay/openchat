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

    private var allResults: [PickerModelItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [PickerModelItem] = []

        for provider in providerStore.enabledProviders {
            if provider.id == "openrouter" {
                // Searching the provider name should surface that provider's full catalog.
                let query = matchesProviderName(provider.name, query: trimmed) ? "" : searchText
                let models = OpenRouterModelCatalog.filtered(
                    models: providerStore.openRouterModels,
                    query: query,
                    capabilities: selectedCapabilities
                )
                items.append(contentsOf: models.map { PickerModelItem(provider: provider, catalogModel: $0) })
            } else {
                items.append(contentsOf: provider.models.compactMap { model in
                    guard matchesFilters(model: model, providerName: provider.name, query: trimmed) else { return nil }
                    return PickerModelItem(provider: provider, model: model)
                })
            }
        }

        return items
    }

    private var emptyFilterMessage: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return "No models match “\(trimmed)”."
        }
        if !selectedCapabilities.isEmpty {
            return "No models match the selected capabilities."
        }
        return "No models available right now."
    }

    private var isOpenRouterLoading: Bool {
        openRouterProvider != nil
            && providerStore.isLoadingOpenRouterModels
            && providerStore.openRouterModels.isEmpty
    }

    private var openRouterError: String? {
        guard openRouterProvider != nil,
              providerStore.openRouterModels.isEmpty,
              let error = providerStore.openRouterModelsError
        else { return nil }
        return error
    }

    var body: some View {
        NavigationStack {
            List {
                if isOpenRouterLoading {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading OpenRouter models…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let error = openRouterError {
                    Section {
                        Text(error)
                            .foregroundStyle(.secondary)
                        Button("Try Again") {
                            providerStore.refreshOpenRouterModelsIfNeeded(force: true)
                        }
                    }
                }

                Section {
                    if allResults.isEmpty, !isOpenRouterLoading {
                        Text(emptyFilterMessage)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(allResults) { item in
                            modelButton(item)
                        }
                    }
                } footer: {
                    if !allResults.isEmpty {
                        Text("\(allResults.count) models")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search models")
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

    private func matchesFilters(model: AIModel, providerName: String, query: String) -> Bool {
        let matchesText = query.isEmpty
            || model.id.localizedCaseInsensitiveContains(query)
            || model.displayName.localizedCaseInsensitiveContains(query)
            || (model.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
            || matchesProviderName(providerName, query: query)
        let matchesCapabilities = ModelCapability.matches(model.capabilities, filters: selectedCapabilities)
        return matchesText && matchesCapabilities
    }

    private func matchesProviderName(_ name: String, query: String) -> Bool {
        guard query.count >= 2 else { return false }
        return name.localizedCaseInsensitiveContains(query)
    }

    private func modelButton(_ item: PickerModelItem) -> some View {
        Button {
            Haptics.light()
            if item.providerID == "openrouter", let catalogModel = item.catalogModel {
                providerStore.rememberOpenRouterModel(catalogModel)
            }
            onSelect(item.providerID, item.modelID)
            dismiss()
        } label: {
            modelRow(item)
        }
    }

    private func modelRow(_ item: PickerModelItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ProviderLogoView(
                        logoAssetName: item.providerLogoAssetName,
                        symbolName: item.providerSymbolName,
                        tint: Color(hex: item.providerTint),
                        size: 14,
                        cornerRadius: 3
                    )
                    Text(providerSubtitle(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            ModelCapabilitySigns(capabilities: item.capabilities)
            if item.providerID == currentProviderID && item.modelID == currentModelID {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.displayName), \(item.providerName)")
    }

    private func providerSubtitle(for item: PickerModelItem) -> String {
        if let subtitle = item.subtitle, !subtitle.isEmpty {
            return "\(item.providerName) · \(subtitle)"
        }
        return item.providerName
    }
}

/// A selectable model row that can come from any enabled provider.
private struct PickerModelItem: Identifiable {
    let id: String
    let providerID: String
    let providerName: String
    let providerSymbolName: String
    let providerTint: String
    let providerLogoAssetName: String?
    let modelID: String
    let displayName: String
    let subtitle: String?
    let capabilities: [ModelCapability]
    /// Present for OpenRouter catalog rows so selection can persist the model.
    let catalogModel: OpenRouterCatalogModel?

    init(provider: ConfiguredProvider, model: AIModel) {
        id = "\(provider.id)/\(model.id)"
        providerID = provider.id
        providerName = provider.name
        providerSymbolName = provider.symbolName
        providerTint = provider.tint
        providerLogoAssetName = provider.logoAssetName
        modelID = model.id
        displayName = model.displayName
        subtitle = model.subtitle
        capabilities = model.capabilities
        catalogModel = nil
    }

    init(provider: ConfiguredProvider, catalogModel: OpenRouterCatalogModel) {
        id = "\(provider.id)/\(catalogModel.id)"
        providerID = provider.id
        providerName = provider.name
        providerSymbolName = provider.symbolName
        providerTint = provider.tint
        providerLogoAssetName = provider.logoAssetName
        modelID = catalogModel.id
        displayName = catalogModel.displayName
        subtitle = catalogModel.subtitle
        capabilities = catalogModel.capabilities
        self.catalogModel = catalogModel
    }
}

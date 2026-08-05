import SwiftUI

struct ModelPickerSheet: View {
    let currentProviderID: String
    let currentModelID: String
    let onSelect: (String, String) -> Void

    @Environment(ProviderStore.self) private var providerStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedProviderIDs: Set<String> = []
    @State private var selectedCapabilities: Set<ModelCapability> = []

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedProviderIDs.isEmpty
            || !selectedCapabilities.isEmpty
    }

    private var filteredItems: [PickerModelItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [PickerModelItem] = []

        for provider in providerStore.enabledProviders {
            if !selectedProviderIDs.isEmpty, !selectedProviderIDs.contains(provider.id) {
                continue
            }

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
                items.append(contentsOf: providerStore.pickerModels(for: provider).compactMap { model in
                    guard matchesFilters(model: model, providerName: provider.name, query: trimmed) else { return nil }
                    return PickerModelItem(provider: provider, model: model)
                })
            }
        }

        return items
    }

    private var partitionedResults: (starred: [PickerModelItem], models: [PickerModelItem]) {
        ProviderStore.partitionForModelPicker(
            filteredItems,
            isFiltering: isFiltering,
            isStarred: { item in
                providerStore.isModelStarred(providerID: item.providerID, modelID: item.modelID)
            },
            usageCount: { item in
                providerStore.modelUsageCount(providerID: item.providerID, modelID: item.modelID)
            }
        )
    }

    private var totalVisibleCount: Int {
        let parts = partitionedResults
        return parts.starred.count + parts.models.count
    }

    private var emptyFilterMessage: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return "No models match “\(trimmed)”."
        }
        if !selectedProviderIDs.isEmpty, !selectedCapabilities.isEmpty {
            return "No models match the selected filters."
        }
        if !selectedProviderIDs.isEmpty {
            return "No models match the selected providers."
        }
        if !selectedCapabilities.isEmpty {
            return "No models match the selected capabilities."
        }
        return "No models available right now."
    }

    private var isInitialLoading: Bool {
        providerStore.isLoadingModels && totalVisibleCount == 0
    }

    private var fetchErrors: [(providerName: String, message: String)] {
        var errors: [(String, String)] = []
        if let message = providerStore.openRouterModelsError,
           providerStore.openRouterModels.isEmpty,
           providerStore.enabledProviders.contains(where: { $0.id == "openrouter" }) {
            errors.append(("OpenRouter", message))
        }
        for provider in providerStore.enabledProviders where provider.id != "openrouter" {
            if let message = providerStore.liveModelErrors[provider.id],
               providerStore.liveModelsByProviderID[provider.id]?.isEmpty ?? true,
               provider.models.isEmpty {
                errors.append((provider.name, message))
            }
        }
        return errors
    }

    var body: some View {
        NavigationStack {
            List {
                if isInitialLoading {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading models…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if !fetchErrors.isEmpty, totalVisibleCount == 0 {
                    Section {
                        ForEach(fetchErrors, id: \.providerName) { error in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(error.providerName)
                                    .font(.subheadline.weight(.semibold))
                                Text(error.message)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Try Again") {
                            providerStore.refreshModelsIfNeeded(force: true)
                        }
                    }
                }

                let parts = partitionedResults

                if totalVisibleCount == 0, !isInitialLoading {
                    Section {
                        Text(emptyFilterMessage)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if !parts.starred.isEmpty {
                        Section {
                            ForEach(parts.starred) { item in
                                modelRow(item)
                            }
                        } header: {
                            Text("Starred")
                        } footer: {
                            if parts.models.isEmpty {
                                Text("\(totalVisibleCount) models")
                            }
                        }
                    }

                    if !parts.models.isEmpty {
                        Section {
                            ForEach(parts.models) { item in
                                modelRow(item)
                            }
                        } header: {
                            if !parts.starred.isEmpty {
                                Text("Models")
                            }
                        } footer: {
                            Text("\(totalVisibleCount) models")
                        }
                    }
                }
            }
            .animation(Theme.springSmooth, value: providerStore.starredModelKeys)
            .searchable(text: $searchText, prompt: "Search models")
            .navigationTitle("Choose a Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        providerStore.refreshModelsIfNeeded(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh models")
                    .disabled(providerStore.isLoadingModels)
                }
            }
            .safeAreaInset(edge: .bottom) {
                ModelPickerFilterBars(
                    providers: providerStore.enabledProviders,
                    selectedProviderIDs: $selectedProviderIDs,
                    selectedCapabilities: $selectedCapabilities
                )
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            providerStore.refreshModelsIfNeeded()
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

    private func modelRow(_ item: PickerModelItem) -> some View {
        let isStarred = providerStore.isModelStarred(providerID: item.providerID, modelID: item.modelID)
        let isCurrent = item.providerID == currentProviderID && item.modelID == currentModelID

        return HStack(spacing: 10) {
            Button {
                select(item)
            } label: {
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
                    if isCurrent {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                            .fontWeight(.semibold)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.displayName), \(item.providerName)")

            starButton(for: item, isStarred: isStarred)
        }
        .contextMenu {
            Button {
                toggleStar(item)
            } label: {
                Label(
                    isStarred ? "Unstar" : "Star",
                    systemImage: isStarred ? "star.slash.fill" : "star.fill"
                )
            }
        }
    }

    private func starButton(for item: PickerModelItem, isStarred: Bool) -> some View {
        Button {
            toggleStar(item)
        } label: {
            Image(systemName: isStarred ? "star.fill" : "star")
                .font(.body)
                .foregroundStyle(isStarred ? Color.orange : Color.secondary.opacity(0.55))
                .frame(width: 28, height: 44)
                .contentShape(Rectangle())
                .symbolEffect(.bounce, value: isStarred)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isStarred ? "Unstar" : "Star")
        .accessibilityAddTraits(isStarred ? .isSelected : [])
    }

    private func toggleStar(_ item: PickerModelItem) {
        Haptics.light()
        withAnimation(Theme.springSmooth) {
            providerStore.toggleStarredModel(providerID: item.providerID, modelID: item.modelID)
        }
    }

    private func select(_ item: PickerModelItem) {
        Haptics.light()
        if let catalogModel = item.catalogModel {
            providerStore.rememberOpenRouterModel(catalogModel)
        } else {
            providerStore.rememberModel(
                AIModel(
                    id: item.modelID,
                    displayName: item.displayName,
                    subtitle: item.subtitle,
                    capabilities: item.capabilities
                ),
                providerID: item.providerID
            )
        }
        onSelect(item.providerID, item.modelID)
        dismiss()
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

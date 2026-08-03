import SwiftUI

struct DataSourcesSettingsView: View {
    @Environment(AgentDataSourceStore.self) private var dataSourceStore
    @State private var pendingSource: AgentDataSource?
    @State private var busySource: AgentDataSource?
    @State private var statusMessage: String?

    var body: some View {
        List {
            Section {
                Label {
                    Text("Agents only use sources you enable. Relevant details may be included in prompts sent to the AI providers you configure. Nothing is shared until a source is on and iOS permission is granted.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.orange)
                }
            }

            ForEach(AgentDataSourceSection.allCases) { section in
                Section {
                    ForEach(section.sources) { source in
                        DataSourceToggleRow(
                            source: source,
                            isOn: dataSourceStore.isEnabled(source),
                            authorizationStatus: dataSourceStore.authorizationStatus(for: source),
                            isBusy: busySource == source,
                            onChange: { enabled in
                                Task { await handleToggle(source, enabled: enabled) }
                            }
                        )
                    }
                } header: {
                    Text(section.title)
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Agent Data Sources")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            pendingSource?.title ?? "Enable source",
            isPresented: Binding(
                get: { pendingSource != nil },
                set: { if !$0 { pendingSource = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Enable") {
                if let source = pendingSource {
                    pendingSource = nil
                    Task { await enable(source) }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingSource = nil
            }
        } message: {
            Text(pendingSource?.confirmationMessage ?? "")
        }
        .onAppear {
            dataSourceStore.refreshAuthorizationStatuses()
        }
    }

    private func handleToggle(_ source: AgentDataSource, enabled: Bool) async {
        if enabled {
            if source.requiresConfirmation {
                pendingSource = source
                return
            }
            await enable(source)
        } else {
            busySource = source
            await dataSourceStore.setEnabled(false, for: source)
            busySource = nil
            statusMessage = nil
            Haptics.light()
        }
    }

    private func enable(_ source: AgentDataSource) async {
        busySource = source
        let status = await dataSourceStore.setEnabled(true, for: source)
        busySource = nil

        switch status {
        case .authorized:
            statusMessage = nil
            Haptics.success()
        case .denied, .restricted:
            statusMessage = "\(source.title) permission was denied. You can enable it in iOS Settings → OpenChat."
            Haptics.error()
        case .unavailable:
            statusMessage = "\(source.title) isn’t available on this device."
            Haptics.error()
        case .notDetermined:
            statusMessage = "\(source.title) permission wasn’t completed."
            Haptics.error()
        }
    }
}

private struct DataSourceToggleRow: View {
    let source: AgentDataSource
    let isOn: Bool
    let authorizationStatus: AgentDataSourceAuthorizationStatus
    let isBusy: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { onChange($0) }
        )) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: source.symbolName)
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                    Text(source.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isOn, authorizationStatus == .denied || authorizationStatus == .restricted {
                        Text("Permission denied — open iOS Settings")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .disabled(isBusy)
    }
}

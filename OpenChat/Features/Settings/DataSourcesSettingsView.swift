import SwiftUI
import UIKit

struct DataSourcesSettingsView: View {
    @Environment(AgentDataSourceStore.self) private var dataSourceStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var busySource: AgentDataSource?
    @State private var statusMessage: String?
    @State private var settingsAlertSource: AgentDataSource?

    var body: some View {
        List {
            Section {
                Label {
                    Text("When enabled, photos you capture or pick can be sent with chat requests so the model can analyze them. "
                         + "Microphone access is used for voice input. Notifications let the agent send follow-ups on this device.")
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
                        toggleRow(for: source)
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
        .onAppear {
            dataSourceStore.refreshAuthorizationStatuses()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                dataSourceStore.refreshAuthorizationStatuses()
            }
        }
        .alert(
            "Permission Needed",
            isPresented: Binding(
                get: { settingsAlertSource != nil },
                set: { if !$0 { settingsAlertSource = nil } }
            ),
            presenting: settingsAlertSource
        ) { _ in
            Button("Open Settings") { openSystemSettings() }
            Button("Cancel", role: .cancel) {}
        } message: { source in
            Text("\(source.title) access was previously denied. iOS only asks once, so re-enabling this toggle can't show the prompt again — open iOS Settings → OpenChat to allow it, then come back here.")
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @ViewBuilder
    private func toggleRow(for source: AgentDataSource) -> some View {
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

    private func handleToggle(_ source: AgentDataSource, enabled: Bool) async {
        if enabled {
            let currentStatus = dataSourceStore.authorizationStatus(for: source)
            if currentStatus == .denied || currentStatus == .restricted {
                settingsAlertSource = source
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
        applyStatus(status, for: source)
    }

    private func applyStatus(_ status: AgentDataSourceAuthorizationStatus, for source: AgentDataSource) {
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

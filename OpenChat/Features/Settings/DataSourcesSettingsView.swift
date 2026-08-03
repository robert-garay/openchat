import SwiftUI

struct DataSourcesSettingsView: View {
    @Environment(AgentDataSourceStore.self) private var dataSourceStore
    @State private var showingFitnessNotice = false
    @State private var showingCalendarAccessChooser = false
    @State private var busySource: AgentDataSource?
    @State private var statusMessage: String?

    var body: some View {
        List {
            Section {
                Label {
                    Text("When enabled, calendar and fitness data are attached to chat requests so the model can answer questions like today’s agenda. With calendar editing on, the model can propose changes you confirm in chat. Relevant details are sent to the AI providers you configure.")
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
                            calendarAccessMode: source == .calendar ? dataSourceStore.calendarAccessMode : nil,
                            isBusy: busySource == source,
                            onChange: { enabled in
                                Task { await handleToggle(source, enabled: enabled) }
                            },
                            onChangeCalendarMode: source == .calendar ? { mode in
                                dataSourceStore.setCalendarAccessMode(mode)
                                Haptics.light()
                            } : nil
                        )
                    }
                } header: {
                    Text(section.title)
                } footer: {
                    if section == .fitness {
                        Text("Fitness metrics only (\(FitnessHealthDataTypes.userFacingSummary)). No clinical records, labs, or medications. Not medical advice.")
                    } else if section == .personal {
                        Text("For Calendar, choose Read only or Read & edit when turning it on. Edits always require confirmation in chat.")
                    } else {
                        EmptyView()
                    }
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
        .sheet(isPresented: $showingFitnessNotice) {
            FitnessPrivacyNoticeView {
                dataSourceStore.acknowledgeFitnessPrivacyNotice()
                showingFitnessNotice = false
                Task { await enable(.appleHealth) }
            } onCancel: {
                showingFitnessNotice = false
            }
        }
        .sheet(isPresented: $showingCalendarAccessChooser) {
            CalendarAccessModeChooserView { mode in
                showingCalendarAccessChooser = false
                Task { await enableCalendar(mode: mode) }
            } onCancel: {
                showingCalendarAccessChooser = false
            }
        }
        .onAppear {
            dataSourceStore.refreshAuthorizationStatuses()
        }
    }

    private func handleToggle(_ source: AgentDataSource, enabled: Bool) async {
        if enabled {
            if source == .calendar {
                showingCalendarAccessChooser = true
                return
            }
            if source.requiresPrivacyNotice && !dataSourceStore.hasAcknowledgedFitnessPrivacyNotice {
                showingFitnessNotice = true
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

    private func enableCalendar(mode: CalendarAccessMode) async {
        busySource = .calendar
        let status = await dataSourceStore.enableCalendar(accessMode: mode)
        busySource = nil
        applyStatus(status, for: .calendar)
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

struct CalendarAccessModeChooserView: View {
    let onSelect: (CalendarAccessMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose how agents may use your calendar. iOS will ask for calendar access either way. Edits are never applied until you confirm them in chat.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                Section("Access level") {
                    ForEach(CalendarAccessMode.allCases) { mode in
                        Button {
                            onSelect(mode)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: mode.symbolName)
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mode.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(mode.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Calendar Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct FitnessPrivacyNoticeView: View {
    let onAgree: () -> Void
    let onCancel: () -> Void
    @State private var acknowledged = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Fitness & Health Privacy")
                        .font(.title2.weight(.semibold))

                    Text("Before OpenChat can read Apple Health, please confirm you understand how this data is used.")
                        .foregroundStyle(.secondary)

                    noticeRow(
                        symbol: "heart.text.square",
                        title: "Fitness metrics only",
                        detail: "OpenChat may read \(FitnessHealthDataTypes.userFacingSummary). This is for coaching-style fitness insights — not medical advice, diagnosis, or treatment."
                    )
                    noticeRow(
                        symbol: "cross.case",
                        title: "No clinical data",
                        detail: "OpenChat does not request clinical records, lab results, medications, immunizations, or other medical chart data from Apple Health."
                    )
                    noticeRow(
                        symbol: "network",
                        title: "Sent to your AI provider",
                        detail: "Relevant fitness metrics may be included in prompts sent to the AI providers you configure (for example OpenAI, Anthropic, or a custom endpoint). OpenChat does not operate its own backend for this data."
                    )
                    noticeRow(
                        symbol: "lock.shield",
                        title: "Under your control",
                        detail: "Apple Health stays off until you enable it. You can turn it off anytime in OpenChat. Revoke system access in iOS Settings → Health → Data Access."
                    )
                    noticeRow(
                        symbol: "eye.slash",
                        title: "No selling or ads",
                        detail: "OpenChat does not sell Health data or use it for advertising or credit decisions."
                    )

                    Toggle(isOn: $acknowledged) {
                        Text("I understand and want to enable Apple Health for fitness insights.")
                            .font(.subheadline)
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button("Agree & Continue") {
                        onAgree()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!acknowledged)
                    .frame(maxWidth: .infinity)

                    Button("Not Now", action: onCancel)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
                .background(.bar)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func noticeRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DataSourceToggleRow: View {
    let source: AgentDataSource
    let isOn: Bool
    let authorizationStatus: AgentDataSourceAuthorizationStatus
    var calendarAccessMode: CalendarAccessMode? = nil
    let isBusy: Bool
    let onChange: (Bool) -> Void
    var onChangeCalendarMode: ((CalendarAccessMode) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if source == .calendar, isOn, let calendarAccessMode, let onChangeCalendarMode {
                Picker("Calendar access", selection: Binding(
                    get: { calendarAccessMode },
                    set: { onChangeCalendarMode($0) }
                )) {
                    ForEach(CalendarAccessMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
}

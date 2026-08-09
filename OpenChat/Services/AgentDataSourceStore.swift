import Foundation
import Observation

/// Persists which on-device data sources the user has enabled for agents,
/// and coordinates iOS permission requests when a source is turned on.
@MainActor
@Observable
final class AgentDataSourceStore {
    private(set) var enabledSourceIDs: Set<String> = []
    private(set) var lastAuthorizationBySource: [AgentDataSource: AgentDataSourceAuthorizationStatus] = [:]
    private(set) var hasAcknowledgedFitnessPrivacyNotice: Bool = false
    private(set) var calendarAccessMode: CalendarAccessMode?
    private(set) var remindersAccessMode: RemindersAccessMode?

    private let defaultsKey = "com.openchat.agentDataSources"
    private let fitnessNoticeKey = "com.openchat.fitnessPrivacyNoticeAcknowledged"
    private let calendarModeKey = "com.openchat.calendarAccessMode"
    private let remindersModeKey = "com.openchat.remindersAccessMode"
    private let defaults: UserDefaults
    private let permissions: AgentDataSourcePermissionService

    init(
        defaults: UserDefaults = .standard,
        permissions: AgentDataSourcePermissionService? = nil
    ) {
        self.defaults = defaults
        self.permissions = permissions ?? AgentDataSourcePermissionService(defaults: defaults)
        load()
        refreshAuthorizationStatuses()
    }

    var enabledCount: Int { enabledSourceIDs.count }

    var enabledSources: [AgentDataSource] {
        AgentDataSource.allCases.filter { enabledSourceIDs.contains($0.rawValue) }
    }

    var canEditCalendar: Bool {
        isAvailableForAgents(.calendar) && calendarAccessMode?.allowsEdits == true
    }

    var canEditReminders: Bool {
        isAvailableForAgents(.reminders) && remindersAccessMode?.allowsEdits == true
    }

    /// Contacts has no partial iOS permission scope — once granted, agents may read and edit.
    var canEditContacts: Bool {
        isAvailableForAgents(.contacts)
    }

    func isEnabled(_ source: AgentDataSource) -> Bool {
        enabledSourceIDs.contains(source.rawValue)
    }

    /// Ready for agents: user opted in and iOS authorization is granted.
    /// Apple Health read grants are opaque on iOS, so the Settings toggle is the source of truth
    /// once Health data is available on the device.
    func isAvailableForAgents(_ source: AgentDataSource) -> Bool {
        guard isEnabled(source) else { return false }
        if source == .appleHealth {
            return authorizationStatus(for: source) != .unavailable
        }
        return authorizationStatus(for: source) == .authorized
    }

    func authorizationStatus(for source: AgentDataSource) -> AgentDataSourceAuthorizationStatus {
        lastAuthorizationBySource[source] ?? permissions.authorizationStatus(for: source)
    }

    func refreshAuthorizationStatuses() {
        var statuses: [AgentDataSource: AgentDataSourceAuthorizationStatus] = [:]
        for source in AgentDataSource.allCases {
            statuses[source] = permissions.authorizationStatus(for: source)
        }
        lastAuthorizationBySource = statuses
    }

    func acknowledgeFitnessPrivacyNotice() {
        hasAcknowledgedFitnessPrivacyNotice = true
        defaults.set(true, forKey: fitnessNoticeKey)
    }

    func setCalendarAccessMode(_ mode: CalendarAccessMode) {
        guard isEnabled(.calendar) else { return }
        calendarAccessMode = mode
        persistCalendarMode()
    }

    func setRemindersAccessMode(_ mode: RemindersAccessMode) {
        guard isEnabled(.reminders) else { return }
        remindersAccessMode = mode
        persistRemindersMode()
    }

    /// Test seam: mark a source as opted-in and authorized without an OS permission prompt.
    func markAvailableForTesting(
        _ source: AgentDataSource,
        calendarMode: CalendarAccessMode? = nil,
        remindersMode: RemindersAccessMode? = nil
    ) {
        enabledSourceIDs.insert(source.rawValue)
        lastAuthorizationBySource[source] = .authorized
        if source == .calendar {
            calendarAccessMode = calendarMode ?? .readOnly
            persistCalendarMode()
        }
        if source == .reminders {
            remindersAccessMode = remindersMode ?? .readOnly
            persistRemindersMode()
        }
        persist()
    }

    @discardableResult
    func enableCalendar(accessMode: CalendarAccessMode) async -> AgentDataSourceAuthorizationStatus {
        let status = await setEnabled(true, for: .calendar)
        if status == .authorized {
            calendarAccessMode = accessMode
            persistCalendarMode()
        } else {
            calendarAccessMode = nil
            persistCalendarMode()
        }
        return status
    }

    @discardableResult
    func enableReminders(accessMode: RemindersAccessMode) async -> AgentDataSourceAuthorizationStatus {
        let status = await setEnabled(true, for: .reminders)
        if status == .authorized {
            remindersAccessMode = accessMode
            persistRemindersMode()
        } else {
            remindersAccessMode = nil
            persistRemindersMode()
        }
        return status
    }

    @discardableResult
    func setEnabled(_ enabled: Bool, for source: AgentDataSource) async -> AgentDataSourceAuthorizationStatus {
        if !enabled {
            enabledSourceIDs.remove(source.rawValue)
            if source == .calendar {
                calendarAccessMode = nil
                persistCalendarMode()
            }
            if source == .reminders {
                remindersAccessMode = nil
                persistRemindersMode()
            }
            persist()
            refreshAuthorizationStatuses()
            return authorizationStatus(for: source)
        }

        if source.requiresPrivacyNotice && !hasAcknowledgedFitnessPrivacyNotice {
            return .notDetermined
        }

        let status = await permissions.requestAccess(for: source)
        lastAuthorizationBySource[source] = status

        switch status {
        case .authorized:
            enabledSourceIDs.insert(source.rawValue)
            if source == .calendar, calendarAccessMode == nil {
                calendarAccessMode = .readOnly
                persistCalendarMode()
            }
            if source == .reminders, remindersAccessMode == nil {
                remindersAccessMode = .readOnly
                persistRemindersMode()
            }
            persist()
        case .denied, .restricted, .unavailable, .notDetermined:
            enabledSourceIDs.remove(source.rawValue)
            if source == .calendar {
                calendarAccessMode = nil
                persistCalendarMode()
            }
            if source == .reminders {
                remindersAccessMode = nil
                persistRemindersMode()
            }
            persist()
        }

        return status
    }

    private func load() {
        hasAcknowledgedFitnessPrivacyNotice = defaults.bool(forKey: fitnessNoticeKey)
        if let raw = defaults.string(forKey: calendarModeKey) {
            calendarAccessMode = CalendarAccessMode(rawValue: raw)
        }
        if let raw = defaults.string(forKey: remindersModeKey) {
            remindersAccessMode = RemindersAccessMode(rawValue: raw)
        }
        guard let values = defaults.array(forKey: defaultsKey) as? [String] else {
            enabledSourceIDs = []
            return
        }
        let valid = Set(AgentDataSource.allCases.map(\.rawValue))
        enabledSourceIDs = Set(values.filter { valid.contains($0) })
        // Drop removed MVP sources (Home, Location, etc.) from persistence.
        persist()
        if !enabledSourceIDs.contains(AgentDataSource.calendar.rawValue) {
            calendarAccessMode = nil
            persistCalendarMode()
        } else if calendarAccessMode == nil {
            calendarAccessMode = .readOnly
            persistCalendarMode()
        }
        if !enabledSourceIDs.contains(AgentDataSource.reminders.rawValue) {
            remindersAccessMode = nil
            persistRemindersMode()
        } else if remindersAccessMode == nil {
            remindersAccessMode = .readOnly
            persistRemindersMode()
        }
        // Keep HealthKit prompt flag aligned with the Settings toggle (read grants are opaque).
        if enabledSourceIDs.contains(AgentDataSource.appleHealth.rawValue) {
            permissions.markHealthPromptCompleted()
        }
    }

    private func persist() {
        defaults.set(Array(enabledSourceIDs).sorted(), forKey: defaultsKey)
    }

    private func persistCalendarMode() {
        if let calendarAccessMode {
            defaults.set(calendarAccessMode.rawValue, forKey: calendarModeKey)
        } else {
            defaults.removeObject(forKey: calendarModeKey)
        }
    }

    private func persistRemindersMode() {
        if let remindersAccessMode {
            defaults.set(remindersAccessMode.rawValue, forKey: remindersModeKey)
        } else {
            defaults.removeObject(forKey: remindersModeKey)
        }
    }
}

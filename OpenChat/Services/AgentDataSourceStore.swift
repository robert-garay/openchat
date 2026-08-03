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

    private let defaultsKey = "com.openchat.agentDataSources"
    private let fitnessNoticeKey = "com.openchat.fitnessPrivacyNoticeAcknowledged"
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

    func isEnabled(_ source: AgentDataSource) -> Bool {
        enabledSourceIDs.contains(source.rawValue)
    }

    /// Ready for agents: user opted in and iOS authorization is granted.
    func isAvailableForAgents(_ source: AgentDataSource) -> Bool {
        isEnabled(source) && authorizationStatus(for: source) == .authorized
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

    @discardableResult
    func setEnabled(_ enabled: Bool, for source: AgentDataSource) async -> AgentDataSourceAuthorizationStatus {
        if !enabled {
            enabledSourceIDs.remove(source.rawValue)
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
            persist()
        case .denied, .restricted, .unavailable, .notDetermined:
            enabledSourceIDs.remove(source.rawValue)
            persist()
        }

        return status
    }

    private func load() {
        hasAcknowledgedFitnessPrivacyNotice = defaults.bool(forKey: fitnessNoticeKey)
        guard let values = defaults.array(forKey: defaultsKey) as? [String] else {
            enabledSourceIDs = []
            return
        }
        let valid = Set(AgentDataSource.allCases.map(\.rawValue))
        enabledSourceIDs = Set(values.filter { valid.contains($0) })
        // Drop removed MVP sources (Home, Location, etc.) from persistence.
        persist()
    }

    private func persist() {
        defaults.set(Array(enabledSourceIDs).sorted(), forKey: defaultsKey)
    }
}

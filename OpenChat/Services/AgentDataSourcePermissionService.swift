import AVFoundation
import EventKit
import HealthKit
import Photos
import UserNotifications

/// Requests and reports iOS authorization for each agent data source.
@MainActor
final class AgentDataSourcePermissionService {
    private let healthStore = HKHealthStore()
    private let defaults: UserDefaults
    private let healthPromptKey = "com.openchat.healthAuthPromptCompleted"
    private var notificationStatus: AgentDataSourceAuthorizationStatus = .notDetermined

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func authorizationStatus(for source: AgentDataSource) -> AgentDataSourceAuthorizationStatus {
        switch source {
        case .appleHealth:
            guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
            // HealthKit hides read grants; we only know the prompt completed.
            return defaults.bool(forKey: healthPromptKey) ? .authorized : .notDetermined
        case .camera:
            return mapAVStatus(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            return mapAVStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        case .photos:
            return mapPhotosStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        case .calendar:
            return mapEventStatus(EKEventStore.authorizationStatus(for: .event))
        case .notifications:
            return notificationStatus
        }
    }

    func requestAccess(for source: AgentDataSource) async -> AgentDataSourceAuthorizationStatus {
        switch source {
        case .appleHealth:
            return await requestHealth()
        case .camera:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .authorized : .denied
        case .microphone:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .authorized : .denied
        case .photos:
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return mapPhotosStatus(status)
        case .calendar:
            return await requestCalendar()
        case .notifications:
            return await requestNotifications()
        }
    }

    // MARK: - Health

    private func requestHealth() async -> AgentDataSourceAuthorizationStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        let types = FitnessHealthDataTypes.readTypes
        do {
            try await healthStore.requestAuthorization(toShare: [], read: types)
            // Read authorization is intentionally opaque on iOS; a completed prompt counts as opted-in.
            markHealthPromptCompleted()
            return .authorized
        } catch {
            return .denied
        }
    }

    func markHealthPromptCompleted() {
        defaults.set(true, forKey: healthPromptKey)
    }

    // MARK: - Calendar / Notifications

    private func requestCalendar() async -> AgentDataSourceAuthorizationStatus {
        let store = EKEventStore()
        do {
            let granted = try await store.requestFullAccessToEvents()
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }

    private func requestNotifications() async -> AgentDataSourceAuthorizationStatus {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            notificationStatus = granted ? .authorized : .denied
            return notificationStatus
        } catch {
            notificationStatus = .denied
            return .denied
        }
    }

    // MARK: - Mapping

    private func mapAVStatus(_ status: AVAuthorizationStatus) -> AgentDataSourceAuthorizationStatus {
        switch status {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private func mapPhotosStatus(_ status: PHAuthorizationStatus) -> AgentDataSourceAuthorizationStatus {
        switch status {
        case .authorized, .limited: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private func mapEventStatus(_ status: EKAuthorizationStatus) -> AgentDataSourceAuthorizationStatus {
        switch status {
        case .fullAccess, .writeOnly: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}

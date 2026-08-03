import AVFoundation
import CoreBluetooth
import CoreLocation
import CoreMotion
import EventKit
import HealthKit
import HomeKit
import Photos
import Contacts
import UserNotifications

/// Requests and reports iOS authorization for each agent data source.
@MainActor
final class AgentDataSourcePermissionService {
    private let healthStore = HKHealthStore()
    private let defaults: UserDefaults
    private let healthPromptKey = "com.openchat.healthAuthPromptCompleted"
    private var locationProbe: LocationPermissionProbe?
    private var bluetoothProbe: BluetoothPermissionProbe?
    private var homeProbe: HomePermissionProbe?
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
        case .home:
            return mapHomeStatus(HMHomeManager.authorizationStatus())
        case .location:
            return mapLocationStatus(CLLocationManager().authorizationStatus)
        case .motion:
            return mapMotionStatus(CMMotionActivityManager.authorizationStatus())
        case .bluetooth:
            return mapBluetoothStatus(CBCentralManager.authorization)
        case .camera:
            return mapAVStatus(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            return mapAVStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        case .photos:
            return mapPhotosStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        case .contacts:
            return mapContactsStatus(CNContactStore.authorizationStatus(for: .contacts))
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
        case .home:
            return await requestHome()
        case .location:
            return await requestLocation()
        case .motion:
            return await requestMotion()
        case .bluetooth:
            return await requestBluetooth()
        case .camera:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .authorized : .denied
        case .microphone:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .authorized : .denied
        case .photos:
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return mapPhotosStatus(status)
        case .contacts:
            return await requestContacts()
        case .calendar:
            return await requestCalendar()
        case .notifications:
            return await requestNotifications()
        }
    }

    // MARK: - Health

    private func healthReadTypes() -> Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        let identifiers: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .activeEnergyBurned,
            .bodyMass,
            .height,
        ]
        for id in identifiers {
            if let type = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    private func requestHealth() async -> AgentDataSourceAuthorizationStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        let types = healthReadTypes()
        do {
            try await healthStore.requestAuthorization(toShare: [], read: types)
            // Read authorization is intentionally opaque on iOS; a completed prompt counts as opted-in.
            defaults.set(true, forKey: healthPromptKey)
            return .authorized
        } catch {
            return .denied
        }
    }

    // MARK: - Home

    private func requestHome() async -> AgentDataSourceAuthorizationStatus {
        let probe = HomePermissionProbe()
        homeProbe = probe
        return await probe.request()
    }

    // MARK: - Location

    private func requestLocation() async -> AgentDataSourceAuthorizationStatus {
        let probe = LocationPermissionProbe()
        locationProbe = probe
        return await probe.request()
    }

    // MARK: - Motion

    private func requestMotion() async -> AgentDataSourceAuthorizationStatus {
        guard CMMotionActivityManager.isActivityAvailable() else { return .unavailable }
        let status = CMMotionActivityManager.authorizationStatus()
        if status != .notDetermined {
            return mapMotionStatus(status)
        }

        let manager = CMMotionActivityManager()
        return await withCheckedContinuation { continuation in
            manager.queryActivityStarting(
                from: Date().addingTimeInterval(-60),
                to: Date(),
                to: .main
            ) { _, error in
                if let error = error as NSError?,
                   error.domain == CMErrorDomain,
                   error.code == Int(CMErrorMotionActivityNotAuthorized.rawValue) {
                    continuation.resume(returning: .denied)
                    return
                }
                let status: AgentDataSourceAuthorizationStatus
                switch CMMotionActivityManager.authorizationStatus() {
                case .authorized: status = .authorized
                case .denied: status = .denied
                case .restricted: status = .restricted
                case .notDetermined: status = .notDetermined
                @unknown default: status = .notDetermined
                }
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Bluetooth

    private func requestBluetooth() async -> AgentDataSourceAuthorizationStatus {
        let probe = BluetoothPermissionProbe()
        bluetoothProbe = probe
        return await probe.request()
    }

    // MARK: - Contacts / Calendar / Notifications

    private func requestContacts() async -> AgentDataSourceAuthorizationStatus {
        let store = CNContactStore()
        do {
            let granted = try await store.requestAccess(for: .contacts)
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }

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

    private func mapContactsStatus(_ status: CNAuthorizationStatus) -> AgentDataSourceAuthorizationStatus {
        switch status {
        case .authorized: .authorized
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

    private func mapLocationStatus(_ status: CLAuthorizationStatus) -> AgentDataSourceAuthorizationStatus {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private func mapMotionStatus(_ status: CMAuthorizationStatus) -> AgentDataSourceAuthorizationStatus {
        switch status {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private func mapBluetoothStatus(_ status: CBManagerAuthorization) -> AgentDataSourceAuthorizationStatus {
        switch status {
        case .allowedAlways: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private func mapHomeStatus(_ status: HMHomeManagerAuthorizationStatus) -> AgentDataSourceAuthorizationStatus {
        if status.contains(.authorized) { return .authorized }
        if status.contains(.restricted) { return .restricted }
        if status.contains(.determined) { return .denied }
        return .notDetermined
    }
}

// MARK: - Permission probes

@MainActor
private final class LocationPermissionProbe: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<AgentDataSourceAuthorizationStatus, Never>?

    func request() async -> AgentDataSourceAuthorizationStatus {
        let current = manager.authorizationStatus
        if current != .notDetermined {
            return map(current)
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard let continuation else { return }
            let status = manager.authorizationStatus
            guard status != .notDetermined else { return }
            self.continuation = nil
            continuation.resume(returning: map(status))
        }
    }

    private func map(_ status: CLAuthorizationStatus) -> AgentDataSourceAuthorizationStatus {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}

@MainActor
private final class BluetoothPermissionProbe: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    private var continuation: CheckedContinuation<AgentDataSourceAuthorizationStatus, Never>?

    func request() async -> AgentDataSourceAuthorizationStatus {
        let current = CBCentralManager.authorization
        if current != .notDetermined {
            return map(current)
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager = CBCentralManager(
                delegate: self,
                queue: nil,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            guard let continuation else { return }
            let status = CBCentralManager.authorization
            guard status != .notDetermined else { return }
            self.continuation = nil
            continuation.resume(returning: map(status))
        }
    }

    private func map(_ status: CBManagerAuthorization) -> AgentDataSourceAuthorizationStatus {
        switch status {
        case .allowedAlways: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}

@MainActor
private final class HomePermissionProbe: NSObject, HMHomeManagerDelegate {
    private var manager: HMHomeManager?
    private var continuation: CheckedContinuation<AgentDataSourceAuthorizationStatus, Never>?

    func request() async -> AgentDataSourceAuthorizationStatus {
        let current = HMHomeManager.authorizationStatus()
        if current.contains(.determined) {
            if current.contains(.authorized) { return .authorized }
            if current.contains(.restricted) { return .restricted }
            return .denied
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let manager = HMHomeManager()
            manager.delegate = self
            self.manager = manager
        }
    }

    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            finish()
        }
    }

    nonisolated func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        Task { @MainActor in
            finish()
        }
    }

    private func finish() {
        guard let continuation else { return }
        let status = HMHomeManager.authorizationStatus()
        guard status.contains(.determined) else { return }
        self.continuation = nil
        if status.contains(.authorized) {
            continuation.resume(returning: .authorized)
        } else if status.contains(.restricted) {
            continuation.resume(returning: .restricted)
        } else {
            continuation.resume(returning: .denied)
        }
    }
}

import AVFoundation
import Photos
import UserNotifications

/// Requests and reports iOS authorization for each agent data source.
@MainActor
final class AgentDataSourcePermissionService {
    private var notificationStatus: AgentDataSourceAuthorizationStatus = .notDetermined

    func authorizationStatus(for source: AgentDataSource) -> AgentDataSourceAuthorizationStatus {
        switch source {
        case .camera:
            return mapAVStatus(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            return mapAVStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        case .photos:
            return mapPhotosStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        case .notifications:
            return notificationStatus
        }
    }

    func requestAccess(for source: AgentDataSource) async -> AgentDataSourceAuthorizationStatus {
        switch source {
        case .camera:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .authorized : .denied
        case .microphone:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .authorized : .denied
        case .photos:
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return mapPhotosStatus(status)
        case .notifications:
            return await requestNotifications()
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
}

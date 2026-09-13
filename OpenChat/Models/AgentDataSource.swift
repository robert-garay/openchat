import Foundation

/// On-device data sources agents may use when the user explicitly opts in.
enum AgentDataSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case camera
    case microphone
    case photos
    case notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .photos: "Photos"
        case .notifications: "Notifications"
        }
    }

    var subtitle: String {
        switch self {
        case .camera: "Capture photos or documents for the agent"
        case .microphone: "Voice input and transcription"
        case .photos: "Analyze images you choose to share"
        case .notifications: "Alerts and follow-ups from the agent"
        }
    }

    var symbolName: String {
        switch self {
        case .camera: "camera.fill"
        case .microphone: "mic.fill"
        case .photos: "photo.on.rectangle"
        case .notifications: "bell.badge.fill"
        }
    }

    var section: AgentDataSourceSection {
        switch self {
        case .camera, .microphone, .photos: .media
        case .notifications: .notifications
        }
    }
}

enum AgentDataSourceSection: String, CaseIterable, Identifiable, Sendable {
    case media
    case notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Media"
        case .notifications: "Notifications"
        }
    }

    var sources: [AgentDataSource] {
        AgentDataSource.allCases.filter { $0.section == self }
    }
}

enum AgentDataSourceAuthorizationStatus: String, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

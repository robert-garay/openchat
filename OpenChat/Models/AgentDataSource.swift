import Foundation

/// On-device data sources agents may use when the user explicitly opts in.
/// MVP keeps the lower-risk set, plus Apple Health behind an explicit fitness disclaimer.
enum AgentDataSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case appleHealth
    case camera
    case microphone
    case photos
    case calendar
    case notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleHealth: "Apple Health"
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .photos: "Photos"
        case .calendar: "Calendar"
        case .notifications: "Notifications"
        }
    }

    var subtitle: String {
        switch self {
        case .appleHealth: "Steps, heart rate, workouts, and related fitness metrics only"
        case .camera: "Capture photos or documents for the agent"
        case .microphone: "Voice input and transcription"
        case .photos: "Analyze images you choose to share"
        case .calendar: "Events and schedules — choose read only or edit when enabling"
        case .notifications: "Reminders and follow-ups from the agent"
        }
    }

    var symbolName: String {
        switch self {
        case .appleHealth: "heart.fill"
        case .camera: "camera.fill"
        case .microphone: "mic.fill"
        case .photos: "photo.on.rectangle"
        case .calendar: "calendar"
        case .notifications: "bell.badge.fill"
        }
    }

    var section: AgentDataSourceSection {
        switch self {
        case .appleHealth: .fitness
        case .camera, .microphone, .photos: .media
        case .calendar, .notifications: .personal
        }
    }

    /// Fitness requires acknowledging the privacy notice before the system permission prompt.
    var requiresPrivacyNotice: Bool {
        self == .appleHealth
    }
}

enum AgentDataSourceSection: String, CaseIterable, Identifiable, Sendable {
    case media
    case personal
    case fitness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Camera & Media"
        case .personal: "Personal"
        case .fitness: "Fitness"
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

import Foundation

/// On-device data sources agents may use when the user explicitly opts in.
/// MVP keeps the lower-risk set, plus Apple Health behind an explicit fitness disclaimer.
enum AgentDataSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case appleHealth
    case camera
    case microphone
    case photos
    case contacts
    case calendar
    case reminders
    case notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleHealth: "Apple Health"
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .photos: "Photos"
        case .contacts: "Contacts"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .notifications: "Notifications"
        }
    }

    var subtitle: String {
        switch self {
        case .appleHealth: "Steps, heart rate, workouts, and related fitness metrics only"
        case .camera: "Capture photos or documents for the agent"
        case .microphone: "Voice input and transcription"
        case .photos: "Analyze images you choose to share"
        case .contacts: "Look up and manage people in your address book"
        case .calendar: "Events and schedules — choose read only or edit when enabling"
        case .reminders: "Tasks and to-dos — choose read only or edit when enabling"
        case .notifications: "Reminders and follow-ups from the agent"
        }
    }

    var symbolName: String {
        switch self {
        case .appleHealth: "heart.fill"
        case .camera: "camera.fill"
        case .microphone: "mic.fill"
        case .photos: "photo.on.rectangle"
        case .contacts: "person.crop.circle.fill"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .notifications: "bell.badge.fill"
        }
    }

    var section: AgentDataSourceSection {
        switch self {
        case .appleHealth: .appleHealth
        case .camera, .microphone, .photos: .media
        case .contacts, .calendar, .reminders: .personal
        case .notifications: .notifications
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
    case notifications
    case appleHealth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Media"
        case .personal: "Personal"
        case .notifications: "Notifications"
        case .appleHealth: "Apple Health"
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

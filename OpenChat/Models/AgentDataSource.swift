import Foundation

/// On-device data sources agents may use when the user explicitly opts in.
enum AgentDataSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case appleHealth
    case home
    case location
    case motion
    case bluetooth
    case camera
    case microphone
    case photos
    case contacts
    case calendar
    case notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleHealth: "Apple Health"
        case .home: "Home"
        case .location: "Location"
        case .motion: "Motion & Fitness"
        case .bluetooth: "Bluetooth Devices"
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .photos: "Photos"
        case .contacts: "Contacts"
        case .calendar: "Calendar"
        case .notifications: "Notifications"
        }
    }

    var subtitle: String {
        switch self {
        case .appleHealth: "Workouts, heart rate, sleep, and activity"
        case .home: "HomeKit scenes, lights, locks, and climate"
        case .location: "Current place and travel context"
        case .motion: "Steps, activity type, and movement"
        case .bluetooth: "Nearby and connected accessories"
        case .camera: "Capture photos or documents for the agent"
        case .microphone: "Voice input and transcription"
        case .photos: "Analyze images you choose to share"
        case .contacts: "People and relationship context"
        case .calendar: "Events, schedules, and meeting prep"
        case .notifications: "Reminders and follow-ups from the agent"
        }
    }

    var symbolName: String {
        switch self {
        case .appleHealth: "heart.fill"
        case .home: "homekit"
        case .location: "location.fill"
        case .motion: "figure.walk"
        case .bluetooth: "wave.3.right"
        case .camera: "camera.fill"
        case .microphone: "mic.fill"
        case .photos: "photo.on.rectangle"
        case .contacts: "person.crop.circle"
        case .calendar: "calendar"
        case .notifications: "bell.badge.fill"
        }
    }

    var section: AgentDataSourceSection {
        switch self {
        case .appleHealth, .home: .healthAndHome
        case .location, .motion, .bluetooth: .sensorsAndDevices
        case .camera, .microphone, .photos: .media
        case .contacts, .calendar, .notifications: .personal
        }
    }

    /// Sources that warrant an extra confirmation before the system permission prompt.
    var requiresConfirmation: Bool {
        switch self {
        case .appleHealth, .home, .contacts, .location: true
        default: false
        }
    }

    var confirmationMessage: String {
        switch self {
        case .appleHealth:
            "Apple Health data is sensitive. If you enable this, agents may include health metrics in prompts sent to the AI providers you configure."
        case .home:
            "Home access lets agents see and control HomeKit accessories. Confirm actions before anything that changes your home."
        case .contacts:
            "Contacts can reveal personal relationships. Agents may include names and details in prompts to your AI provider."
        case .location:
            "Location reveals where you are. Agents may include place context in prompts to your AI provider."
        default:
            "This source may be included in prompts sent to the AI providers you configure."
        }
    }
}

enum AgentDataSourceSection: String, CaseIterable, Identifiable, Sendable {
    case healthAndHome
    case sensorsAndDevices
    case media
    case personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .healthAndHome: "Health & Home"
        case .sensorsAndDevices: "Sensors & Devices"
        case .media: "Camera & Media"
        case .personal: "Personal"
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

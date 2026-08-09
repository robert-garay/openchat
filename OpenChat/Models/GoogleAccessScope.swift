import Foundation

/// OAuth 2.0 scopes used to access Google core apps from OpenChat.
enum GoogleAccessScope: String, CaseIterable, Codable, Identifiable, Sendable {
    case calendarReadonly = "https://www.googleapis.com/auth/calendar.readonly"
    case calendarEvents = "https://www.googleapis.com/auth/calendar.events"
    case gmailReadonly = "https://www.googleapis.com/auth/gmail.readonly"
    case driveReadonly = "https://www.googleapis.com/auth/drive.readonly"

    var id: String { rawValue }

    /// User-facing name for this permission.
    var title: String {
        switch self {
        case .calendarReadonly: "Read Calendar"
        case .calendarEvents: "Edit Calendar"
        case .gmailReadonly: "Read Gmail"
        case .driveReadonly: "Read Drive"
        }
    }

    /// Which core Google app this scope belongs to.
    var app: GoogleApp {
        switch self {
        case .calendarReadonly, .calendarEvents: .calendar
        case .gmailReadonly: .gmail
        case .driveReadonly: .drive
        }
    }

    /// Whether this scope allows write access.
    var isWrite: Bool {
        switch self {
        case .calendarEvents: true
        case .calendarReadonly, .gmailReadonly, .driveReadonly: false
        }
    }
}

/// The core Google apps integrated into OpenChat.
enum GoogleApp: String, CaseIterable, Codable, Identifiable, Sendable {
    case calendar
    case gmail
    case drive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: "Google Calendar"
        case .gmail: "Gmail"
        case .drive: "Google Drive"
        }
    }

    var symbolName: String {
        switch self {
        case .calendar: "calendar"
        case .gmail: "envelope.fill"
        case .drive: "folder.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .calendar:
            "Include upcoming events in agent context and propose edits you confirm in chat."
        case .gmail:
            "Include recent email context so agents can summarize threads or find messages."
        case .drive:
            "Let agents search and read files you reference in conversation."
        }
    }

    /// Readonly scope for this app.
    var readScope: GoogleAccessScope {
        switch self {
        case .calendar: .calendarReadonly
        case .gmail: .gmailReadonly
        case .drive: .driveReadonly
        }
    }

    /// Write scope for this app, if any.
    var writeScope: GoogleAccessScope? {
        switch self {
        case .calendar: .calendarEvents
        case .gmail, .drive: nil
        }
    }

    /// All scopes required to enable this app (read + optional write).
    var allScopes: [GoogleAccessScope] {
        if let writeScope { return [readScope, writeScope] }
        return [readScope]
    }
}

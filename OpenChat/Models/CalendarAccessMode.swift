import Foundation

/// App-level calendar permission scope. iOS EventKit full access is requested for both;
/// write tools are gated by this mode.
enum CalendarAccessMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case readOnly
    case readWrite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readOnly: "Read only"
        case .readWrite: "Read & edit"
        }
    }

    var detail: String {
        switch self {
        case .readOnly:
            "Agents can see your agenda and answer schedule questions. They cannot change events."
        case .readWrite:
            "Agents can propose new, updated, or deleted events. Nothing is changed until you confirm in chat."
        }
    }

    var symbolName: String {
        switch self {
        case .readOnly: "eye"
        case .readWrite: "calendar.badge.plus"
        }
    }

    var allowsEdits: Bool { self == .readWrite }

    var shortLabel: String {
        switch self {
        case .readOnly: "Read only"
        case .readWrite: "Can edit"
        }
    }
}

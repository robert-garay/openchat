import EventKit
import Foundation

enum CalendarEventWriterError: LocalizedError {
    case editingDisabled
    case missingDefaultCalendar
    case eventNotFound
    case invalidTimeRange
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .editingDisabled:
            return "Calendar editing is turned off in Settings."
        case .missingDefaultCalendar:
            return "No default calendar is available for new events."
        case .eventNotFound:
            return "That calendar event could not be found."
        case .invalidTimeRange:
            return "The event end time must be after the start time."
        case .saveFailed(let message):
            return message
        }
    }
}

/// Applies confirmed calendar create/update/delete proposals via EventKit.
enum CalendarEventWriter {
    @MainActor
    static func apply(
        _ proposal: CalendarActionProposal,
        eventStore: EKEventStore = EKEventStore()
    ) throws -> String {
        switch proposal.type {
        case .create:
            return try create(proposal, eventStore: eventStore)
        case .update:
            return try update(proposal, eventStore: eventStore)
        case .delete:
            return try delete(proposal, eventStore: eventStore)
        }
    }

    @MainActor
    private static func create(_ proposal: CalendarActionProposal, eventStore: EKEventStore) throws -> String {
        guard let title = proposal.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let start = proposal.start, let end = proposal.end else {
            throw CalendarEventWriterError.invalidTimeRange
        }
        guard end >= start else { throw CalendarEventWriterError.invalidTimeRange }
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarEventWriterError.missingDefaultCalendar
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = proposal.isAllDay ?? false
        event.location = proposal.location
        event.notes = proposal.notes

        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            throw CalendarEventWriterError.saveFailed(error.localizedDescription)
        }
        return "Created \"\(title)\"."
    }

    @MainActor
    private static func update(_ proposal: CalendarActionProposal, eventStore: EKEventStore) throws -> String {
        guard let identifier = proposal.eventIdentifier,
              let event = eventStore.event(withIdentifier: identifier) else {
            throw CalendarEventWriterError.eventNotFound
        }

        if let title = proposal.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            event.title = title
        }
        if let start = proposal.start { event.startDate = start }
        if let end = proposal.end { event.endDate = end }
        if let isAllDay = proposal.isAllDay { event.isAllDay = isAllDay }
        if let location = proposal.location { event.location = location }
        if let notes = proposal.notes { event.notes = notes }

        guard event.endDate >= event.startDate else {
            throw CalendarEventWriterError.invalidTimeRange
        }

        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            throw CalendarEventWriterError.saveFailed(error.localizedDescription)
        }
        let name = event.title ?? "event"
        return "Updated \"\(name)\"."
    }

    @MainActor
    private static func delete(_ proposal: CalendarActionProposal, eventStore: EKEventStore) throws -> String {
        guard let identifier = proposal.eventIdentifier,
              let event = eventStore.event(withIdentifier: identifier) else {
            throw CalendarEventWriterError.eventNotFound
        }
        let title = event.title ?? "event"
        do {
            try eventStore.remove(event, span: .thisEvent)
        } catch {
            throw CalendarEventWriterError.saveFailed(error.localizedDescription)
        }
        return "Deleted \"\(title)\"."
    }
}

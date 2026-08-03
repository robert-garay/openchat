import EventKit
import Foundation

struct CalendarEventSnapshot: Equatable, Sendable {
    var eventIdentifier: String? = nil
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
}

/// Reads opted-in calendar events for agent context.
enum CalendarContextReader {
    /// Today and tomorrow in the user's current calendar/timezone.
    static func fetchUpcomingEvents(
        now: Date = .now,
        calendar: Calendar = .current,
        eventStore: EKEventStore = EKEventStore()
    ) -> [CalendarEventSnapshot] {
        let dayStart = calendar.startOfDay(for: now)
        guard let rangeEnd = calendar.date(byAdding: .day, value: 2, to: dayStart) else { return [] }

        let predicate = eventStore.predicateForEvents(withStart: dayStart, end: rangeEnd, calendars: nil)
        return eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map {
                let title = ($0.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let location = ($0.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return CalendarEventSnapshot(
                    eventIdentifier: $0.eventIdentifier,
                    title: title.isEmpty ? "Untitled" : title,
                    start: $0.startDate,
                    end: $0.endDate,
                    isAllDay: $0.isAllDay,
                    location: location.isEmpty ? nil : location
                )
            }
    }

    static func contextSection(
        events: [CalendarEventSnapshot],
        now: Date = .now,
        calendar: Calendar = .current,
        accessMode: CalendarAccessMode = .readOnly
    ) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = .current
        dayFormatter.dateStyle = .full
        dayFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = .current
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

        func eventsOnDay(_ day: Date) -> [CalendarEventSnapshot] {
            let start = calendar.startOfDay(for: day)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
            return events.filter { $0.start < end && $0.end > start }
        }

        func formatDay(_ day: Date, label: String) -> String {
            let dayEvents = eventsOnDay(day)
            let header = "### \(label) — \(dayFormatter.string(from: day))"
            guard !dayEvents.isEmpty else {
                return "\(header)\n- No events"
            }
            let lines = dayEvents.map { event -> String in
                let when: String
                if event.isAllDay {
                    when = "All day"
                } else {
                    when = "\(timeFormatter.string(from: event.start))–\(timeFormatter.string(from: event.end))"
                }
                var line = "- \(when): \(event.title)"
                if let location = event.location {
                    line += " (\(location))"
                }
                if accessMode.allowsEdits, let id = event.eventIdentifier, !id.isEmpty {
                    line += " [id: \(id)]"
                    line += " {start: \(isoFormatter.string(from: event.start)), end: \(isoFormatter.string(from: event.end))}"
                }
                return line
            }
            return ([header] + lines).joined(separator: "\n")
        }

        let body = [
            formatDay(todayStart, label: "Today"),
            formatDay(tomorrowStart, label: "Tomorrow"),
        ].joined(separator: "\n\n")

        var section = "## Calendar (\(accessMode.shortLabel))\n\(body)"
        if accessMode.allowsEdits {
            section += """


            ### Calendar edits
            You may propose calendar changes. Never claim an event was changed until the user confirms in the OpenChat UI.
            When proposing changes, put ONLY machine-readable JSON in a fenced block like:

            ```openchat-calendar
            {"actions":[{"type":"create","title":"Title","start":"2026-08-04T15:00:00Z","end":"2026-08-04T16:00:00Z","location":null,"isAllDay":false}]}
            ```

            Allowed action types: create, update, delete.
            For update/delete, use eventIdentifier from the [id: ...] values above.
            Dates must be ISO-8601. Keep the visible reply human-readable and brief about what you propose.
            """
        } else {
            section += "\n\nCalendar is read only. Do not claim you can create, edit, or delete events."
        }
        return section
    }

    static func contextSection(
        now: Date = .now,
        calendar: Calendar = .current,
        accessMode: CalendarAccessMode = .readOnly
    ) -> String {
        let events = fetchUpcomingEvents(now: now, calendar: calendar)
        return contextSection(events: events, now: now, calendar: calendar, accessMode: accessMode)
    }
}

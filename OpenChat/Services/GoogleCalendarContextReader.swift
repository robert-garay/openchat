import Foundation

struct GoogleCalendarEventSnapshot: Equatable, Sendable {
    var eventIdentifier: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var htmlLink: String?
}

/// Reads opted-in Google Calendar events for agent context.
enum GoogleCalendarContextReader {
    private static let endpoint = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!

    /// Fetch today and tomorrow's events from the user's primary Google Calendar.
    static func fetchUpcomingEvents(
        for accountID: UUID,
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> [GoogleCalendarEventSnapshot] {
        let dayStart = calendar.startOfDay(for: now)
        guard let rangeEnd = calendar.date(byAdding: .day, value: 2, to: dayStart) else { return [] }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: isoFormatter.string(from: dayStart)),
            URLQueryItem(name: "timeMax", value: isoFormatter.string(from: rangeEnd)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "20"),
        ]

        guard let url = components.url else { return [] }

        do {
            let response: EventsResponse = try await GoogleAPIClient.get(url, for: accountID)
            return response.items.compactMap { event -> GoogleCalendarEventSnapshot? in
                guard let dates = parseDates(event: event) else { return nil }
                let title = (event.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
                return GoogleCalendarEventSnapshot(
                    eventIdentifier: event.id,
                    title: title.isEmpty ? "Untitled" : title,
                    start: dates.start,
                    end: dates.end,
                    isAllDay: dates.isAllDay,
                    location: location?.isEmpty == false ? location : nil,
                    htmlLink: event.htmlLink
                )
            }
        } catch {
            return []
        }
    }

    static func contextSection(
        for accountID: UUID,
        now: Date = .now,
        calendar: Calendar = .current,
        includeEditInstructions: Bool = false
    ) async -> String? {
        let events = await fetchUpcomingEvents(for: accountID, now: now, calendar: calendar)
        return contextSection(
            events: events,
            now: now,
            calendar: calendar,
            includeEditInstructions: includeEditInstructions
        )
    }

    static func contextSection(
        events: [GoogleCalendarEventSnapshot],
        now: Date = .now,
        calendar: Calendar = .current,
        includeEditInstructions: Bool = false
    ) -> String? {
        guard !events.isEmpty else { return nil }

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

        func eventsOnDay(_ day: Date) -> [GoogleCalendarEventSnapshot] {
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
                if includeEditInstructions {
                    line += " [id: \(event.eventIdentifier)]"
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

        var section = "## Google Calendar\n\(body)"
        if includeEditInstructions {
            section += """


            ### Google Calendar edits
            You may propose calendar changes. Never claim an event was changed until the user confirms in the OpenChat UI.
            When proposing changes, put ONLY machine-readable JSON in a fenced block like:

            ```openchat-google-calendar
            {"actions":[{"type":"create","title":"Title","start":"2026-08-04T15:00:00Z","end":"2026-08-04T16:00:00Z","location":null,"isAllDay":false}]}
            ```

            Allowed action types: create, update, delete.
            For update/delete, use eventIdentifier from the [id: ...] values above.
            Dates must be ISO-8601. Keep the visible reply human-readable and brief about what you propose.
            """
        }
        return section
    }

    // MARK: - Wire types

    private struct EventsResponse: Decodable, Sendable {
        var items: [EventItem]
    }

    private struct EventItem: Decodable, Sendable {
        var id: String
        var summary: String?
        var start: EventDateTime
        var end: EventDateTime
        var location: String?
        var htmlLink: String?
    }

    private struct EventDateTime: Decodable, Sendable {
        var date: String?
        var dateTime: String?
    }

    private struct ParsedEventDates: Sendable {
        var start: Date
        var end: Date
        var isAllDay: Bool
    }

    private static let googleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private static func parseDates(event: EventItem) -> ParsedEventDates? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        if let dateString = event.start.date, let endDateString = event.end.date {
            guard let start = googleDateFormatter.date(from: dateString),
                  let end = googleDateFormatter.date(from: endDateString) else { return nil }
            return ParsedEventDates(start: start, end: end, isAllDay: true)
        }

        if let startString = event.start.dateTime, let endString = event.end.dateTime {
            guard let start = isoFormatter.date(from: startString),
                  let end = isoFormatter.date(from: endString) else { return nil }
            return ParsedEventDates(start: start, end: end, isAllDay: false)
        }

        return nil
    }
}

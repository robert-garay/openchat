import EventKit
import Foundation

struct ReminderSnapshot: Equatable, Sendable {
    var reminderIdentifier: String? = nil
    var title: String
    var dueDate: Date?
    var isCompleted: Bool
    var notes: String?
}

/// Reads opted-in reminders for agent context.
enum RemindersContextReader {
    @MainActor
    static func fetchReminders(eventStore: EKEventStore = EKEventStore()) async -> [ReminderSnapshot] {
        let predicate = eventStore.predicateForReminders(in: nil)
        let snapshots: [ReminderSnapshot] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let mapped = (reminders ?? [])
                    .filter { !$0.isCompleted }
                    .sorted { lhs, rhs in
                        switch (lhs.dueDateComponents?.date, rhs.dueDateComponents?.date) {
                        case let (l?, r?): return l < r
                        case (nil, _): return false
                        case (_, nil): return true
                        }
                    }
                    .map { reminder -> ReminderSnapshot in
                        let title = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let notes = (reminder.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return ReminderSnapshot(
                            reminderIdentifier: reminder.calendarItemIdentifier,
                            title: title.isEmpty ? "Untitled" : title,
                            dueDate: reminder.dueDateComponents?.date,
                            isCompleted: reminder.isCompleted,
                            notes: notes.isEmpty ? nil : notes
                        )
                    }
                continuation.resume(returning: mapped)
            }
        }
        return snapshots
    }

    static func contextSection(
        reminders: [ReminderSnapshot],
        calendar: Calendar = .current,
        accessMode: RemindersAccessMode = .readOnly
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = .current
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let body: String
        if reminders.isEmpty {
            body = "- No open reminders"
        } else {
            body = reminders.map { reminder -> String in
                var line = "- \(reminder.title)"
                if let dueDate = reminder.dueDate {
                    line += " (due \(dateFormatter.string(from: dueDate)))"
                }
                if accessMode.allowsEdits, let id = reminder.reminderIdentifier, !id.isEmpty {
                    line += " [id: \(id)]"
                    if let dueDate = reminder.dueDate {
                        line += " {due: \(isoFormatter.string(from: dueDate))}"
                    }
                }
                return line
            }.joined(separator: "\n")
        }

        var section = "## Reminders (\(accessMode.shortLabel))\n\(body)"
        if accessMode.allowsEdits {
            section += """


            ### Reminders edits
            You may propose reminder changes. Never claim a reminder was changed until the user confirms in the OpenChat UI.
            When proposing changes, put ONLY machine-readable JSON in a fenced block like:

            ```openchat-reminders
            {"actions":[{"type":"create","title":"Title","dueDate":"2026-08-04T15:00:00Z","notes":null}]}
            ```

            Allowed action types: create, update, delete.
            For update/delete, use reminderIdentifier from the [id: ...] values above.
            Dates must be ISO-8601. Keep the visible reply human-readable and brief about what you propose.
            """
        } else {
            section += "\n\nReminders is read only. Do not claim you can create, edit, or delete reminders."
        }
        return section
    }

    @MainActor
    static func contextSection(
        calendar: Calendar = .current,
        accessMode: RemindersAccessMode = .readOnly
    ) async -> String {
        let reminders = await fetchReminders()
        return contextSection(reminders: reminders, calendar: calendar, accessMode: accessMode)
    }
}

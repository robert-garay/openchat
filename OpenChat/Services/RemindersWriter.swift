import EventKit
import Foundation

enum RemindersWriterError: LocalizedError {
    case editingDisabled
    case missingDefaultList
    case reminderNotFound
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .editingDisabled:
            return "Reminders editing is turned off in Settings."
        case .missingDefaultList:
            return "No default reminders list is available for new reminders."
        case .reminderNotFound:
            return "That reminder could not be found."
        case .saveFailed(let message):
            return message
        }
    }
}

/// Applies confirmed reminder create/update/delete proposals via EventKit.
enum RemindersWriter {
    static func apply(
        _ proposal: RemindersActionProposal,
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

    private static func create(_ proposal: RemindersActionProposal, eventStore: EKEventStore) throws -> String {
        guard let title = proposal.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            throw RemindersWriterError.saveFailed("A title is required.")
        }
        guard let list = eventStore.defaultCalendarForNewReminders() else {
            throw RemindersWriterError.missingDefaultList
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = list
        reminder.title = title
        reminder.notes = proposal.notes
        if let dueDate = proposal.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw RemindersWriterError.saveFailed(error.localizedDescription)
        }
        return "Created \"\(title)\"."
    }

    private static func update(_ proposal: RemindersActionProposal, eventStore: EKEventStore) throws -> String {
        guard let reminder = findReminder(identifier: proposal.reminderIdentifier, eventStore: eventStore) else {
            throw RemindersWriterError.reminderNotFound
        }

        if let title = proposal.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            reminder.title = title
        }
        if let notes = proposal.notes { reminder.notes = notes }
        if let dueDate = proposal.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        if let isCompleted = proposal.isCompleted { reminder.isCompleted = isCompleted }

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw RemindersWriterError.saveFailed(error.localizedDescription)
        }
        let name = reminder.title ?? "reminder"
        return "Updated \"\(name)\"."
    }

    private static func delete(_ proposal: RemindersActionProposal, eventStore: EKEventStore) throws -> String {
        guard let reminder = findReminder(identifier: proposal.reminderIdentifier, eventStore: eventStore) else {
            throw RemindersWriterError.reminderNotFound
        }
        let title = reminder.title ?? "reminder"
        do {
            try eventStore.remove(reminder, commit: true)
        } catch {
            throw RemindersWriterError.saveFailed(error.localizedDescription)
        }
        return "Deleted \"\(title)\"."
    }

    private static func findReminder(identifier: String?, eventStore: EKEventStore) -> EKReminder? {
        guard let identifier, !identifier.isEmpty,
              let item = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return nil
        }
        return item
    }
}

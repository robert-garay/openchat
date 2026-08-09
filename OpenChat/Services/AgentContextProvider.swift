import Foundation

/// Builds ephemeral on-device context for chat requests from sources the user enabled.
/// Context is injected into the model request only — it is not stored in chat history.
@MainActor
struct AgentContextProvider {
    var dataSourceStore: AgentDataSourceStore
    var memoryItems: [MemoryItem] = []
    var calendarSection: (CalendarAccessMode) -> String? = { mode in
        CalendarContextReader.contextSection(accessMode: mode)
    }
    var remindersSection: (RemindersAccessMode) async -> String? = { mode in
        await RemindersContextReader.contextSection(accessMode: mode)
    }
    var contactsSection: (Bool) -> String? = { canEdit in
        ContactsContextReader.contextSection(canEdit: canEdit)
    }
    var fitnessSection: () async -> String? = {
        await FitnessContextReader.contextSection()
    }
    var memorySection: ([MemoryItem]) -> String? = { items in
        MemoryStore.contextSection(for: items)
    }

    func makeContextBlock() async -> String? {
        var sections: [String] = []

        if dataSourceStore.isAvailableForAgents(.calendar) {
            let mode = dataSourceStore.calendarAccessMode ?? .readOnly
            if let calendar = calendarSection(mode) {
                sections.append(calendar)
            }
        }

        if dataSourceStore.isAvailableForAgents(.reminders) {
            let mode = dataSourceStore.remindersAccessMode ?? .readOnly
            if let reminders = await remindersSection(mode) {
                sections.append(reminders)
            }
        }

        if dataSourceStore.isAvailableForAgents(.contacts) {
            if let contacts = contactsSection(dataSourceStore.canEditContacts) {
                sections.append(contacts)
            }
        }

        if dataSourceStore.isAvailableForAgents(.appleHealth),
           let fitness = await fitnessSection() {
            sections.append(fitness)
        }

        if !memoryItems.isEmpty, let memory = memorySection(memoryItems) {
            sections.append(memory)
        }

        guard !sections.isEmpty else { return nil }

        return """
        On-device context the user enabled in OpenChat settings. Use it when relevant. \
        Do not invent calendar events, reminders, contacts, fitness metrics, or memory facts beyond what appears here. \
        If the user asks about agenda/schedule, prefer the Calendar section. \
        If they ask about tasks or to-dos, prefer the Reminders section. \
        If they ask about people or their contact details, prefer the Contacts section. \
        If they ask about steps, heart rate, workouts, sleep, or training, prefer the Fitness section. \
        If they ask about saved preferences or long-term facts, prefer the Memory section.

        \(sections.joined(separator: "\n\n"))
        """
    }
}

import Foundation

/// Builds ephemeral on-device context for chat requests from sources the user enabled.
/// Context is injected into the model request only — it is not stored in chat history.
@MainActor
struct AgentContextProvider {
    var dataSourceStore: AgentDataSourceStore
    var calendarSection: (CalendarAccessMode) -> String? = { mode in
        CalendarContextReader.contextSection(accessMode: mode)
    }
    var fitnessSection: () async -> String? = {
        await FitnessContextReader.contextSection()
    }

    func makeContextBlock() async -> String? {
        var sections: [String] = []

        if dataSourceStore.isAvailableForAgents(.calendar) {
            let mode = dataSourceStore.calendarAccessMode ?? .readOnly
            if let calendar = calendarSection(mode) {
                sections.append(calendar)
            }
        }

        if dataSourceStore.isAvailableForAgents(.appleHealth),
           let fitness = await fitnessSection() {
            sections.append(fitness)
        }

        guard !sections.isEmpty else { return nil }

        return """
        On-device context the user enabled in OpenChat settings. Use it when relevant. Do not invent calendar events or fitness metrics beyond what appears here. If the user asks about agenda/schedule, prefer the Calendar section. If they ask about steps, heart rate, workouts, sleep, or training, prefer the Fitness section.

        \(sections.joined(separator: "\n\n"))
        """
    }
}

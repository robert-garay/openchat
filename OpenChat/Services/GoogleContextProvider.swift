import Foundation

/// Builds ephemeral Google-app context for chat requests from connected accounts.
enum GoogleContextProvider {
    /// Gather context sections from all connected, enabled Google accounts.
    static func makeContextBlock(
        accounts: [GoogleAccount],
        calendarSection: (UUID) async -> String? = { accountID in
            await GoogleCalendarContextReader.contextSection(for: accountID)
        },
        gmailSection: (UUID) async -> String? = { accountID in
            await GmailContextReader.contextSection(for: accountID)
        },
        driveSection: (UUID) async -> String? = { accountID in
            await GoogleDriveContextReader.contextSection(for: accountID)
        }
    ) async -> String? {
        var sections: [String] = []

        for account in accounts {
            let accountHeader = "### Account: \(account.email)"
            var accountSections: [String] = []

            if account.isConnected(to: .calendar),
               account.enabledAppRawValues.contains(GoogleApp.calendar.rawValue),
               let calendar = await calendarSection(account.id) {
                accountSections.append(calendar)
            }

            if account.isConnected(to: .gmail),
               account.enabledAppRawValues.contains(GoogleApp.gmail.rawValue),
               let gmail = await gmailSection(account.id) {
                accountSections.append(gmail)
            }

            if account.isConnected(to: .drive),
               account.enabledAppRawValues.contains(GoogleApp.drive.rawValue),
               let drive = await driveSection(account.id) {
                accountSections.append(drive)
            }

            if !accountSections.isEmpty {
                sections.append(([accountHeader] + accountSections).joined(separator: "\n\n"))
            }
        }

        guard !sections.isEmpty else { return nil }

        return """
        Google account context the user enabled in OpenChat settings. Use it when relevant. \
        Do not invent calendar events, emails, or files beyond what appears here. \
        If the user asks about agenda/schedule, prefer the Google Calendar section. \
        If they ask about email, prefer the Gmail section. \
        If they ask about files, prefer the Google Drive section.

        \(sections.joined(separator: "\n\n"))
        """
    }
}

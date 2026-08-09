import Foundation

struct GmailMessageSnapshot: Equatable, Sendable {
    var id: String
    var threadID: String
    var subject: String
    var from: String
    var snippet: String
    var date: Date?
    var labels: [String]
}

/// Reads opted-in Gmail messages for agent context.
enum GmailContextReader {
    private static let listEndpoint = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
    private static let batchGetEndpoint = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/batchGet")!

    /// Fetch recent inbox messages. Defaults to the 5 most recent messages from the last 7 days.
    static func fetchRecentMessages(
        for accountID: UUID,
        maxResults: Int = 5,
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> [GmailMessageSnapshot] {
        guard let afterDate = calendar.date(byAdding: .day, value: -7, to: now) else { return [] }
        let afterSeconds = Int(afterDate.timeIntervalSince1970)
        let query = "in:inbox after:\(afterSeconds)"

        var listComponents = URLComponents(url: listEndpoint, resolvingAgainstBaseURL: true)!
        listComponents.queryItems = [
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "labelIds", value: "INBOX"),
        ]

        guard let listURL = listComponents.url else { return [] }

        do {
            let listResponse: MessageListResponse = try await GoogleAPIClient.get(listURL, for: accountID)
            let messageIDs = listResponse.messages?.map(\.id) ?? []
            guard !messageIDs.isEmpty else { return [] }

            var detailComponents = URLComponents(url: batchGetEndpoint, resolvingAgainstBaseURL: true)!
            detailComponents.queryItems = messageIDs.map { URLQueryItem(name: "ids", value: $0) }
                + [URLQueryItem(name: "format", value: "metadata")]

            guard let detailURL = detailComponents.url else { return [] }
            let detailsResponse: BatchGetResponse = try await GoogleAPIClient.get(detailURL, for: accountID)

            return detailsResponse.messages?.compactMap { message -> GmailMessageSnapshot? in
                let headers = Dictionary(uniqueKeysWithValues: message.payload?.headers?.compactMap { header in
                    header.value.map { (header.name.lowercased(), $0) }
                } ?? [])
                let subject = headers["subject"] ?? "(no subject)"
                let from = headers["from"] ?? "Unknown sender"
                let dateString = headers["date"]
                let date = dateString.flatMap { parseDate($0) }
                return GmailMessageSnapshot(
                    id: message.id,
                    threadID: message.threadId,
                    subject: subject,
                    from: from,
                    snippet: message.snippet ?? "",
                    date: date,
                    labels: message.labelIds ?? []
                )
            } ?? []
        } catch {
            return []
        }
    }

    static func contextSection(
        for accountID: UUID,
        maxResults: Int = 5,
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> String? {
        let messages = await fetchRecentMessages(for: accountID, maxResults: maxResults, now: now, calendar: calendar)
        return contextSection(messages: messages)
    }

    static func contextSection(messages: [GmailMessageSnapshot]) -> String? {
        guard !messages.isEmpty else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        let lines = messages.map { message -> String in
            let date = message.date.map { " (\(dateFormatter.string(from: $0)))" } ?? ""
            let snippet = message.snippet.isEmpty ? "" : " — \(message.snippet)"
            return "- \(message.from)\(date): \(message.subject)\(snippet)"
        }

        return """
        ## Gmail (recent inbox)
        \(lines.joined(separator: "\n"))

        Gmail is read only. You cannot send, archive, or delete emails.
        """
    }

    // MARK: - Wire types

    private struct MessageListResponse: Decodable, Sendable {
        var messages: [MessageReference]?
    }

    private struct MessageReference: Decodable, Sendable {
        var id: String
        var threadId: String
    }

    private struct BatchGetResponse: Decodable, Sendable {
        var messages: [MessageDetail]?
    }

    private struct MessageDetail: Decodable, Sendable {
        var id: String
        var threadId: String
        var snippet: String?
        var labelIds: [String]?
        var payload: MessagePayload?
    }

    private struct MessagePayload: Decodable, Sendable {
        var headers: [MessageHeader]?
    }

    private struct MessageHeader: Decodable, Sendable {
        var name: String
        var value: String?
    }

    private static let rfc2822Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    private static func parseDate(_ value: String) -> Date? {
        rfc2822Formatter.date(from: value)
    }
}

import Foundation

/// A reminder change proposed by the model. Applied only after explicit user confirmation.
struct RemindersActionProposal: Equatable, Identifiable, Sendable, Codable {
    enum ActionType: String, Codable, Sendable {
        case create
        case update
        case delete
    }

    var id: UUID = UUID()
    var type: ActionType
    var reminderIdentifier: String?
    var title: String?
    var dueDate: Date?
    var notes: String?
    var isCompleted: Bool?

    var summaryTitle: String {
        switch type {
        case .create: "Create reminder"
        case .update: "Update reminder"
        case .delete: "Delete reminder"
        }
    }

    var summaryDetail: String {
        switch type {
        case .create:
            return describeReminder(title: title ?? "Untitled", dueDate: dueDate)
        case .update:
            var parts: [String] = []
            if let title { parts.append(title) }
            if let dueDate { parts.append(describeWhen(dueDate)) }
            if parts.isEmpty { parts.append("Reminder \(reminderIdentifier ?? "")") }
            return parts.joined(separator: " · ")
        case .delete:
            if let title, !title.isEmpty { return title }
            return "Reminder \(reminderIdentifier ?? "")"
        }
    }

    private func describeReminder(title: String, dueDate: Date?) -> String {
        guard let dueDate else { return title }
        return "\(title) · \(describeWhen(dueDate))"
    }

    private func describeWhen(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

enum RemindersActionParser {
    private static let fencePattern = #"```openchat-reminders\s*([\s\S]*?)```"#

    static func parse(_ markdown: String) -> [RemindersActionProposal] {
        guard let regex = try? NSRegularExpression(pattern: fencePattern, options: []) else { return [] }
        let nsRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        var proposals: [RemindersActionProposal] = []

        regex.enumerateMatches(in: markdown, options: [], range: nsRange) { match, _, _ in
            guard let match,
                  let bodyRange = Range(match.range(at: 1), in: markdown) else { return }
            let body = String(markdown[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            proposals.append(contentsOf: decodeProposals(from: body))
        }
        return proposals
    }

    /// Removes machine-only reminders fences so they are not shown in the chat bubble.
    static func strippingFences(from markdown: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: fencePattern, options: []) else {
            return markdown
        }
        let nsRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let stripped = regex.stringByReplacingMatches(in: markdown, options: [], range: nsRange, withTemplate: "")
        return stripped
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeProposals(from body: String) -> [RemindersActionProposal] {
        let data = Data(body.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseISO8601(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(raw)")
        }

        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            return envelope.actions.compactMap(Self.normalized)
        }
        if let single = try? decoder.decode(RawAction.self, from: data),
           let normalized = normalized(single) {
            return [normalized]
        }
        if let many = try? decoder.decode([RawAction].self, from: data) {
            return many.compactMap(Self.normalized)
        }
        return []
    }

    /// Parses ISO-8601 without capturing non-Sendable formatters across `@Sendable` decode closures.
    private static func parseISO8601(_ raw: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static func normalized(_ raw: RawAction) -> RemindersActionProposal? {
        guard let type = RemindersActionProposal.ActionType(rawValue: raw.type) else { return nil }
        switch type {
        case .create:
            guard let title = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return nil
            }
        case .update, .delete:
            guard let id = raw.reminderIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
                return nil
            }
        }

        return RemindersActionProposal(
            type: type,
            reminderIdentifier: raw.reminderIdentifier,
            title: raw.title,
            dueDate: raw.dueDate,
            notes: raw.notes,
            isCompleted: raw.isCompleted
        )
    }

    private struct Envelope: Decodable {
        var actions: [RawAction]
    }

    private struct RawAction: Decodable {
        var type: String
        var reminderIdentifier: String?
        var title: String?
        var dueDate: Date?
        var notes: String?
        var isCompleted: Bool?
    }
}

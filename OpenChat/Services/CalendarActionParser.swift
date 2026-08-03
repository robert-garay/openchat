import Foundation

/// A calendar change proposed by the model. Applied only after explicit user confirmation.
struct CalendarActionProposal: Equatable, Identifiable, Sendable, Codable {
    enum ActionType: String, Codable, Sendable {
        case create
        case update
        case delete
    }

    var id: UUID = UUID()
    var type: ActionType
    var eventIdentifier: String?
    var title: String?
    var start: Date?
    var end: Date?
    var location: String?
    var notes: String?
    var isAllDay: Bool?

    var summaryTitle: String {
        switch type {
        case .create: "Create event"
        case .update: "Update event"
        case .delete: "Delete event"
        }
    }

    var summaryDetail: String {
        switch type {
        case .create:
            return describeEvent(title: title ?? "Untitled", start: start, end: end, location: location, isAllDay: isAllDay)
        case .update:
            var parts: [String] = []
            if let title { parts.append(title) }
            if start != nil || end != nil {
                parts.append(describeWhen(start: start, end: end, isAllDay: isAllDay))
            }
            if let location, !location.isEmpty { parts.append(location) }
            if parts.isEmpty { parts.append("Event \(eventIdentifier ?? "")") }
            return parts.joined(separator: " · ")
        case .delete:
            if let title, !title.isEmpty { return title }
            return "Event \(eventIdentifier ?? "")"
        }
    }

    private func describeEvent(
        title: String,
        start: Date?,
        end: Date?,
        location: String?,
        isAllDay: Bool?
    ) -> String {
        var parts = [title, describeWhen(start: start, end: end, isAllDay: isAllDay)]
        if let location, !location.isEmpty { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    private func describeWhen(start: Date?, end: Date?, isAllDay: Bool?) -> String {
        guard let start else { return "Time TBD" }
        let day = start.formatted(date: .abbreviated, time: .omitted)
        let startTime = start.formatted(date: .omitted, time: .shortened)
        if isAllDay == true {
            return "All day \(day)"
        }
        if let end {
            let endTime = end.formatted(date: .omitted, time: .shortened)
            return "\(day) \(startTime)–\(endTime)"
        }
        return "\(day) \(startTime)"
    }
}

enum CalendarActionParser {
    private static let fencePattern = #"```openchat-calendar\s*([\s\S]*?)```"#

    static func parse(_ markdown: String) -> [CalendarActionProposal] {
        guard let regex = try? NSRegularExpression(pattern: fencePattern, options: []) else { return [] }
        let nsRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        var proposals: [CalendarActionProposal] = []

        regex.enumerateMatches(in: markdown, options: [], range: nsRange) { match, _, _ in
            guard let match,
                  let bodyRange = Range(match.range(at: 1), in: markdown) else { return }
            let body = String(markdown[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            proposals.append(contentsOf: decodeProposals(from: body))
        }
        return proposals
    }

    /// Removes machine-only calendar fences so they are not shown in the chat bubble.
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

    private static func decodeProposals(from body: String) -> [CalendarActionProposal] {
        let data = Data(body.utf8)
        let decoder = JSONDecoder()
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = withFractional.date(from: raw) ?? plain.date(from: raw) {
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

    private static func normalized(_ raw: RawAction) -> CalendarActionProposal? {
        guard let type = CalendarActionProposal.ActionType(rawValue: raw.type) else { return nil }
        switch type {
        case .create:
            guard let title = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  let start = raw.start, let end = raw.end, end >= start else { return nil }
        case .update, .delete:
            guard let id = raw.eventIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
                return nil
            }
        }

        return CalendarActionProposal(
            type: type,
            eventIdentifier: raw.eventIdentifier,
            title: raw.title,
            start: raw.start,
            end: raw.end,
            location: raw.location,
            notes: raw.notes,
            isAllDay: raw.isAllDay
        )
    }

    private struct Envelope: Decodable {
        var actions: [RawAction]
    }

    private struct RawAction: Decodable {
        var type: String
        var eventIdentifier: String?
        var title: String?
        var start: Date?
        var end: Date?
        var location: String?
        var notes: String?
        var isAllDay: Bool?
    }
}

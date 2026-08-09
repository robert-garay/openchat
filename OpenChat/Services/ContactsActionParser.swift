import Foundation

/// A contact change proposed by the model. Applied only after explicit user confirmation.
struct ContactsActionProposal: Equatable, Identifiable, Sendable, Codable {
    enum ActionType: String, Codable, Sendable {
        case create
        case update
        case delete
    }

    var id: UUID = UUID()
    var type: ActionType
    var contactIdentifier: String?
    var givenName: String?
    var familyName: String?
    var phoneNumbers: [String]?
    var emailAddresses: [String]?

    var summaryTitle: String {
        switch type {
        case .create: "Create contact"
        case .update: "Update contact"
        case .delete: "Delete contact"
        }
    }

    var summaryDetail: String {
        let name = [givenName, familyName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        switch type {
        case .create:
            return describeContact(name: name.isEmpty ? "Unnamed contact" : name)
        case .update:
            var parts: [String] = []
            if !name.isEmpty { parts.append(name) }
            if let phoneNumbers, !phoneNumbers.isEmpty { parts.append(phoneNumbers.joined(separator: ", ")) }
            if let emailAddresses, !emailAddresses.isEmpty { parts.append(emailAddresses.joined(separator: ", ")) }
            if parts.isEmpty { parts.append("Contact \(contactIdentifier ?? "")") }
            return parts.joined(separator: " · ")
        case .delete:
            if !name.isEmpty { return name }
            return "Contact \(contactIdentifier ?? "")"
        }
    }

    private func describeContact(name: String) -> String {
        var parts = [name]
        if let phoneNumbers, !phoneNumbers.isEmpty { parts.append(phoneNumbers.joined(separator: ", ")) }
        if let emailAddresses, !emailAddresses.isEmpty { parts.append(emailAddresses.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

enum ContactsActionParser {
    private static let fencePattern = #"```openchat-contacts\s*([\s\S]*?)```"#

    static func parse(_ markdown: String) -> [ContactsActionProposal] {
        guard let regex = try? NSRegularExpression(pattern: fencePattern, options: []) else { return [] }
        let nsRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        var proposals: [ContactsActionProposal] = []

        regex.enumerateMatches(in: markdown, options: [], range: nsRange) { match, _, _ in
            guard let match,
                  let bodyRange = Range(match.range(at: 1), in: markdown) else { return }
            let body = String(markdown[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            proposals.append(contentsOf: decodeProposals(from: body))
        }
        return proposals
    }

    /// Removes machine-only contacts fences so they are not shown in the chat bubble.
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

    private static func decodeProposals(from body: String) -> [ContactsActionProposal] {
        let data = Data(body.utf8)
        let decoder = JSONDecoder()

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

    private static func normalized(_ raw: RawAction) -> ContactsActionProposal? {
        guard let type = ContactsActionProposal.ActionType(rawValue: raw.type) else { return nil }
        switch type {
        case .create:
            let given = raw.givenName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let family = raw.familyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !given.isEmpty || !family.isEmpty else { return nil }
        case .update, .delete:
            guard let id = raw.contactIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
                return nil
            }
        }

        return ContactsActionProposal(
            type: type,
            contactIdentifier: raw.contactIdentifier,
            givenName: raw.givenName,
            familyName: raw.familyName,
            phoneNumbers: raw.phoneNumbers,
            emailAddresses: raw.emailAddresses
        )
    }

    private struct Envelope: Decodable {
        var actions: [RawAction]
    }

    private struct RawAction: Decodable {
        var type: String
        var contactIdentifier: String?
        var givenName: String?
        var familyName: String?
        var phoneNumbers: [String]?
        var emailAddresses: [String]?
    }
}

import Contacts
import Foundation

struct ContactSnapshot: Equatable, Sendable {
    var contactIdentifier: String? = nil
    var givenName: String
    var familyName: String
    var phoneNumbers: [String]
    var emailAddresses: [String]

    var fullName: String {
        let name = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Unnamed contact" : name
    }
}

/// Reads opted-in contacts for agent context.
enum ContactsContextReader {
    static var keysToFetch: [CNKeyDescriptor] {
        [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
    }

    static func fetchContacts(contactStore: CNContactStore = CNContactStore(), limit: Int = 200) -> [ContactSnapshot] {
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        var snapshots: [ContactSnapshot] = []
        try? contactStore.enumerateContacts(with: request) { contact, stop in
            snapshots.append(
                ContactSnapshot(
                    contactIdentifier: contact.identifier,
                    givenName: contact.givenName,
                    familyName: contact.familyName,
                    phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue },
                    emailAddresses: contact.emailAddresses.map { $0.value as String }
                )
            )
            if snapshots.count >= limit { stop.pointee = true }
        }
        return snapshots.sorted { $0.fullName < $1.fullName }
    }

    static func contextSection(
        contacts: [ContactSnapshot],
        canEdit: Bool
    ) -> String {
        let body: String
        if contacts.isEmpty {
            body = "- No contacts"
        } else {
            body = contacts.map { contact -> String in
                var line = "- \(contact.fullName)"
                var details: [String] = []
                if let phone = contact.phoneNumbers.first { details.append(phone) }
                if let email = contact.emailAddresses.first { details.append(email) }
                if !details.isEmpty { line += " (\(details.joined(separator: ", ")))" }
                if canEdit, let id = contact.contactIdentifier, !id.isEmpty {
                    line += " [id: \(id)]"
                }
                return line
            }.joined(separator: "\n")
        }

        var section = "## Contacts (\(canEdit ? "Can edit" : "Read only"))\n\(body)"
        if canEdit {
            section += """


            ### Contacts edits
            You may propose contact changes. Never claim a contact was changed until the user confirms in the OpenChat UI.
            When proposing changes, put ONLY machine-readable JSON in a fenced block like:

            ```openchat-contacts
            {"actions":[{"type":"create","givenName":"Jane","familyName":"Doe","phoneNumbers":["555-1234"],"emailAddresses":["jane@example.com"]}]}
            ```

            Allowed action types: create, update, delete.
            For update/delete, use contactIdentifier from the [id: ...] values above.
            Keep the visible reply human-readable and brief about what you propose.
            """
        } else {
            section += "\n\nContacts is read only. Do not claim you can create, edit, or delete contacts."
        }
        return section
    }

    static func contextSection(canEdit: Bool) -> String {
        let contacts = fetchContacts()
        return contextSection(contacts: contacts, canEdit: canEdit)
    }
}

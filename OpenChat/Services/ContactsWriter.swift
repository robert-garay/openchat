import Contacts
import Foundation

enum ContactsWriterError: LocalizedError {
    case editingDisabled
    case contactNotFound
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .editingDisabled:
            return "Contacts editing is turned off in Settings."
        case .contactNotFound:
            return "That contact could not be found."
        case .saveFailed(let message):
            return message
        }
    }
}

/// Applies confirmed contact create/update/delete proposals via the Contacts framework.
enum ContactsWriter {
    static func apply(
        _ proposal: ContactsActionProposal,
        contactStore: CNContactStore = CNContactStore()
    ) throws -> String {
        switch proposal.type {
        case .create:
            return try create(proposal, contactStore: contactStore)
        case .update:
            return try update(proposal, contactStore: contactStore)
        case .delete:
            return try delete(proposal, contactStore: contactStore)
        }
    }

    private static func create(_ proposal: ContactsActionProposal, contactStore: CNContactStore) throws -> String {
        let contact = CNMutableContact()
        contact.givenName = proposal.givenName ?? ""
        contact.familyName = proposal.familyName ?? ""
        contact.phoneNumbers = (proposal.phoneNumbers ?? []).map {
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0))
        }
        contact.emailAddresses = (proposal.emailAddresses ?? []).map {
            CNLabeledValue(label: CNLabelHome, value: $0 as NSString)
        }

        let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        guard !name.isEmpty else {
            throw ContactsWriterError.saveFailed("A name is required.")
        }

        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        do {
            try contactStore.execute(request)
        } catch {
            throw ContactsWriterError.saveFailed(error.localizedDescription)
        }
        return "Created \"\(name)\"."
    }

    private static func update(_ proposal: ContactsActionProposal, contactStore: CNContactStore) throws -> String {
        guard let mutable = fetchMutable(identifier: proposal.contactIdentifier, contactStore: contactStore) else {
            throw ContactsWriterError.contactNotFound
        }

        if let givenName = proposal.givenName { mutable.givenName = givenName }
        if let familyName = proposal.familyName { mutable.familyName = familyName }
        if let phoneNumbers = proposal.phoneNumbers {
            mutable.phoneNumbers = phoneNumbers.map {
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0))
            }
        }
        if let emailAddresses = proposal.emailAddresses {
            mutable.emailAddresses = emailAddresses.map {
                CNLabeledValue(label: CNLabelHome, value: $0 as NSString)
            }
        }

        let request = CNSaveRequest()
        request.update(mutable)
        do {
            try contactStore.execute(request)
        } catch {
            throw ContactsWriterError.saveFailed(error.localizedDescription)
        }
        let name = [mutable.givenName, mutable.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return "Updated \"\(name.isEmpty ? "contact" : name)\"."
    }

    private static func delete(_ proposal: ContactsActionProposal, contactStore: CNContactStore) throws -> String {
        guard let mutable = fetchMutable(identifier: proposal.contactIdentifier, contactStore: contactStore) else {
            throw ContactsWriterError.contactNotFound
        }
        let name = [mutable.givenName, mutable.familyName].filter { !$0.isEmpty }.joined(separator: " ")

        let request = CNSaveRequest()
        request.delete(mutable)
        do {
            try contactStore.execute(request)
        } catch {
            throw ContactsWriterError.saveFailed(error.localizedDescription)
        }
        return "Deleted \"\(name.isEmpty ? "contact" : name)\"."
    }

    private static func fetchMutable(identifier: String?, contactStore: CNContactStore) -> CNMutableContact? {
        guard let identifier, !identifier.isEmpty else { return nil }
        let keys = ContactsContextReader.keysToFetch
        guard let contact = try? contactStore.unifiedContact(withIdentifier: identifier, keysToFetch: keys) else {
            return nil
        }
        return contact.mutableCopy() as? CNMutableContact
    }
}

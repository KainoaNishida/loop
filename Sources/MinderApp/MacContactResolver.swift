import Contacts
import Foundation
import MinderCore

final class MacContactResolver: ContactResolving {
    private let store: CNContactStore
    private var cache: [String: String]?

    init(store: CNContactStore = CNContactStore()) {
        self.store = store
    }

    func displayName(for handle: String) -> String? {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            return nil
        }
        if cache == nil {
            cache = loadContactIndex()
        }
        for key in ContactHandleNormalizer.lookupKeys(for: handle) {
            if let name = cache?[key] {
                return name
            }
        }
        return nil
    }

    private func loadContactIndex() -> [String: String] {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var index: [String: String] = [:]

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                guard let name = Self.displayName(for: contact) else { return }
                for number in contact.phoneNumbers {
                    for key in ContactHandleNormalizer.lookupKeys(for: number.value.stringValue) {
                        index[key] = name
                    }
                }
                for email in contact.emailAddresses {
                    for key in ContactHandleNormalizer.lookupKeys(for: String(email.value)) {
                        index[key] = name
                    }
                }
            }
        } catch {
            return [:]
        }

        return index
    }

    private static func displayName(for contact: CNContact) -> String? {
        let givenFamily = [contact.givenName, contact.familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !givenFamily.isEmpty {
            return givenFamily
        }
        let organization = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return organization.isEmpty ? nil : organization
    }
}

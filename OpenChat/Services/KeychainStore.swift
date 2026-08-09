import Foundation
import Security

/// Thin wrapper around the Keychain Services API for storing provider API
/// keys. Nothing ever touches disk in plaintext.
enum KeychainStore {
    /// The keychain service name. Tests may change this to an isolated value so
    /// repeated runs do not share keychain state with the production app or each
    /// other. In production this value is never modified; tests always set it
    /// from a single sequential `setUp` hook, so `nonisolated(unsafe)` is safe.
    nonisolated(unsafe) static var service = "com.openchat.apikeys"

    static func set(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery(for: key) as CFDictionary, update as CFDictionary)
            if updateStatus != errSecSuccess {
                SecItemDelete(baseQuery(for: key) as CFDictionary)
                SecItemAdd(query as CFDictionary, nil)
            }
        }
    }

    static func get(_ key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    /// Delete every item stored under the current ``service``. Intended for test
    /// cleanup only.
    static func removeAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

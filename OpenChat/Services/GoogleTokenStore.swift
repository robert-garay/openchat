import Foundation

/// Tokens returned by Google's OAuth token endpoint.
struct GoogleTokenResponse: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int
    var tokenType: String
    var scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

/// Keychain-backed storage for a Google account's OAuth tokens.
enum GoogleTokenStore {
    private static func accessTokenKey(for accountID: UUID) -> String {
        "com.openchat.google.tokens.access.\(accountID.uuidString)"
    }

    private static func refreshTokenKey(for accountID: UUID) -> String {
        "com.openchat.google.tokens.refresh.\(accountID.uuidString)"
    }

    private static func expirationKey(for accountID: UUID) -> String {
        "com.openchat.google.tokens.expiration.\(accountID.uuidString)"
    }

    static func store(_ response: GoogleTokenResponse, for accountID: UUID) {
        KeychainStore.set(response.accessToken, forKey: accessTokenKey(for: accountID))
        if let refreshToken = response.refreshToken {
            KeychainStore.set(refreshToken, forKey: refreshTokenKey(for: accountID))
        }
        let expiration = Date().addingTimeInterval(TimeInterval(response.expiresIn))
        UserDefaults.standard.set(expiration.timeIntervalSince1970, forKey: expirationKey(for: accountID))
    }

    static func accessToken(for accountID: UUID) -> String? {
        KeychainStore.get(accessTokenKey(for: accountID))
    }

    static func refreshToken(for accountID: UUID) -> String? {
        KeychainStore.get(refreshTokenKey(for: accountID))
    }

    static func isExpired(for accountID: UUID, leeway: TimeInterval = 60) -> Bool {
        let timestamp = UserDefaults.standard.double(forKey: expirationKey(for: accountID))
        guard timestamp > 0 else { return true }
        return Date().addingTimeInterval(leeway) >= Date(timeIntervalSince1970: timestamp)
    }

    static func remove(for accountID: UUID) {
        KeychainStore.remove(accessTokenKey(for: accountID))
        KeychainStore.remove(refreshTokenKey(for: accountID))
        UserDefaults.standard.removeObject(forKey: expirationKey(for: accountID))
    }
}

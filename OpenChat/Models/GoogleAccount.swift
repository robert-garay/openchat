import Foundation
import SwiftData

/// A Google account connected to OpenChat.
/// Tokens are stored in the Keychain; this model only holds metadata and enabled scopes.
@Model
final class GoogleAccount {
    @Attribute(.unique) var id: UUID
    var email: String
    var name: String?
    var pictureURLString: String?
    var connectedScopeRawValues: [String]
    var enabledAppRawValues: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        email: String,
        name: String? = nil,
        pictureURLString: String? = nil,
        connectedScopes: [GoogleAccessScope] = [],
        enabledApps: [GoogleApp] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.pictureURLString = pictureURLString
        self.connectedScopeRawValues = connectedScopes.map(\.rawValue)
        self.enabledAppRawValues = enabledApps.map(\.rawValue)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var pictureURL: URL? {
        guard let pictureURLString else { return nil }
        return URL(string: pictureURLString)
    }

    var connectedScopes: [GoogleAccessScope] {
        connectedScopeRawValues.compactMap { GoogleAccessScope(rawValue: $0) }
    }

    func setConnectedScopes(_ scopes: [GoogleAccessScope]) {
        connectedScopeRawValues = scopes.map(\.rawValue)
        updatedAt = .now
    }

    func isConnected(to app: GoogleApp) -> Bool {
        connectedScopes.contains(app.readScope)
    }

    func hasWriteAccess(for app: GoogleApp) -> Bool {
        guard let writeScope = app.writeScope else { return false }
        return connectedScopes.contains(writeScope)
    }
}

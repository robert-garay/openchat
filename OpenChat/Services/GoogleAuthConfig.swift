import Foundation

/// Build-time configuration for Google OAuth.
/// Values are injected through Info.plist variables set in `project.yml`
/// and overridden in `Config/Local.xcconfig`.
enum GoogleAuthConfig {
    private static let clientIDKey = "GoogleOAuthClientID"
    private static let redirectURIKey = "GoogleOAuthRedirectURI"

    static var clientID: String? {
        let value = Bundle.main.infoDictionary?[clientIDKey] as? String
        return value?.isEmpty == false ? value : nil
    }

    static var redirectURI: String? {
        let value = Bundle.main.infoDictionary?[redirectURIKey] as? String
        return value?.isEmpty == false ? value : nil
    }

    static var isConfigured: Bool {
        clientID != nil && redirectURI != nil
    }

    static var authorizationEndpoint: URL {
        URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    }

    static var tokenEndpoint: URL {
        URL(string: "https://oauth2.googleapis.com/token")!
    }

    static var revokeEndpoint: URL {
        URL(string: "https://oauth2.googleapis.com/revoke")!
    }

    static var userInfoEndpoint: URL {
        URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
    }

    /// The URL scheme extracted from the redirect URI, used to register the
    /// ASWebAuthenticationSession callback.
    static var redirectURLScheme: String? {
        guard let redirectURI else { return nil }
        return URL(string: redirectURI)?.scheme
    }
}

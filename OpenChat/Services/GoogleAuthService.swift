import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

enum GoogleAuthError: Error, Equatable {
    case notConfigured
    case invalidRedirectURL
    case authorizationDenied
    case invalidAuthorizationResponse
    case missingAuthorizationCode
    case tokenExchangeFailed(String)
    case missingRefreshToken
    case userInfoFailed(String)
    case unsupportedPresentationContext
}

/// Profile information returned by Google's userinfo endpoint.
struct GoogleUserInfo: Codable, Sendable {
    var id: String
    var email: String
    var name: String?
    var picture: String?
}

/// Handles Google OAuth 2.0 sign-in, token refresh, and revocation using PKCE.
@MainActor
final class GoogleAuthService: NSObject {
    static let shared = GoogleAuthService()

    private var currentSession: ASWebAuthenticationSession?

    /// Connect a Google account with the requested scopes.
    /// Returns the account metadata and stores tokens in the Keychain.
    func signIn(scopes: [GoogleAccessScope]) async throws -> (account: GoogleAccount, tokenResponse: GoogleTokenResponse) {
        guard GoogleAuthConfig.isConfigured else {
            throw GoogleAuthError.notConfigured
        }
        guard let redirectURI = GoogleAuthConfig.redirectURI,
              let redirectURL = URL(string: redirectURI),
              let redirectScheme = redirectURL.scheme else {
            throw GoogleAuthError.invalidRedirectURL
        }

        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let state = generateState()

        var components = URLComponents(url: GoogleAuthConfig.authorizationEndpoint, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.map(\.rawValue).joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
        ]

        guard let authURL = components.url else {
            throw GoogleAuthError.invalidAuthorizationResponse
        }

        let callbackURL = try await authenticate(url: authURL, scheme: redirectScheme)

        guard let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true)?.queryItems else {
            throw GoogleAuthError.invalidAuthorizationResponse
        }

        let items = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        if let error = items["error"] {
            throw GoogleAuthError.authorizationDenied
        }

        guard items["state"] == state else {
            throw GoogleAuthError.invalidAuthorizationResponse
        }

        guard let code = items["code"] else {
            throw GoogleAuthError.missingAuthorizationCode
        }

        let tokenResponse = try await exchangeCode(code, codeVerifier: codeVerifier, redirectURI: redirectURI)
        guard tokenResponse.refreshToken != nil else {
            throw GoogleAuthError.missingRefreshToken
        }

        let userInfo = try await fetchUserInfo(accessToken: tokenResponse.accessToken)
        let account = GoogleAccount(
            email: userInfo.email,
            name: userInfo.name,
            pictureURLString: userInfo.picture,
            connectedScopes: scopes
        )
        GoogleTokenStore.store(tokenResponse, for: account.id)

        return (account, tokenResponse)
    }

    /// Refresh the access token for an existing account.
    func refreshAccessToken(for accountID: UUID) async throws -> String {
        guard GoogleAuthConfig.isConfigured else {
            throw GoogleAuthError.notConfigured
        }
        guard let refreshToken = GoogleTokenStore.refreshToken(for: accountID) else {
            throw GoogleAuthError.missingRefreshToken
        }

        var request = URLRequest(url: GoogleAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: GoogleAuthConfig.clientID),
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GoogleAuthError.tokenExchangeFailed(message)
        }

        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        GoogleTokenStore.store(tokenResponse, for: accountID)
        return tokenResponse.accessToken
    }

    /// Ensure a non-expired access token is available, refreshing if necessary.
    func validAccessToken(for accountID: UUID) async throws -> String {
        if let token = GoogleTokenStore.accessToken(for: accountID), !GoogleTokenStore.isExpired(for: accountID) {
            return token
        }
        return try await refreshAccessToken(for: accountID)
    }

    /// Revoke the OAuth grant and remove stored tokens.
    func revoke(accountID: UUID) async throws {
        if let token = GoogleTokenStore.refreshToken(for: accountID) ?? GoogleTokenStore.accessToken(for: accountID) {
            var request = URLRequest(url: GoogleAuthConfig.revokeEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var body = URLComponents()
            body.queryItems = [URLQueryItem(name: "token", value: token)]
            request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
            _ = try? await URLSession.shared.data(for: request)
        }
        GoogleTokenStore.remove(for: accountID)
    }

    // MARK: - Private

    private func authenticate(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GoogleAuthError.invalidAuthorizationResponse)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.currentSession = session
            session.start()
        }
    }

    private func exchangeCode(_ code: String, codeVerifier: String, redirectURI: String) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: GoogleAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "client_id", value: GoogleAuthConfig.clientID),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GoogleAuthError.tokenExchangeFailed(message)
        }

        return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
    }

    private func fetchUserInfo(accessToken: String) async throws -> GoogleUserInfo {
        var request = URLRequest(url: GoogleAuthConfig.userInfoEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GoogleAuthError.userInfoFailed(message)
        }

        return try JSONDecoder().decode(GoogleUserInfo.self, from: data)
    }

    private func generateCodeVerifier() -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<128).map { _ in characters.randomElement()! })
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = Data(SHA256.hash(data: data))
        return base64URLEncode(hash)
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateState() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first else {
                return UIWindow()
            }
            return window
        }
    }
}

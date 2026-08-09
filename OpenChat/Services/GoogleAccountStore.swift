import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class GoogleAccountStore {
    private(set) var accounts: [GoogleAccount] = []
    private(set) var isConfigured: Bool = false
    private(set) var isSigningIn: Bool = false
    private(set) var lastError: String?

    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.isConfigured = GoogleAuthConfig.isConfigured
        fetchAccounts()
    }

    var hasConnectedAccount: Bool { !accounts.isEmpty }

    func account(for id: UUID) -> GoogleAccount? {
        accounts.first { $0.id == id }
    }

    func isEnabled(_ app: GoogleApp, for account: GoogleAccount) -> Bool {
        account.enabledAppRawValues.contains(app.rawValue)
    }

    /// Toggle whether a connected app's data is included in agent context.
    func setEnabled(_ enabled: Bool, app: GoogleApp, for account: GoogleAccount) {
        var enabledApps = Set(account.enabledAppRawValues)
        if enabled {
            guard account.isConnected(to: app) else { return }
            enabledApps.insert(app.rawValue)
        } else {
            enabledApps.remove(app.rawValue)
        }
        account.enabledAppRawValues = Array(enabledApps)
        account.updatedAt = .now
        save()
        Haptics.light()
    }

    /// Sign in with Google and request scopes for the selected apps.
    func signIn(apps: [GoogleApp] = GoogleApp.allCases) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }

        do {
            let scopes = apps.flatMap(\.allScopes)
            let (account, _) = try await GoogleAuthService.shared.signIn(scopes: scopes)
            // Enable the selected apps by default.
            account.enabledAppRawValues = apps.map(\.rawValue)
            modelContainer.mainContext.insert(account)
            save()
            fetchAccounts()
            Haptics.success()
        } catch GoogleAuthError.notConfigured {
            lastError = "Google OAuth is not configured. Set GOOGLE_OAUTH_CLIENT_ID in Local.xcconfig."
            Haptics.error()
        } catch {
            lastError = "Could not connect Google account: \(error.localizedDescription)"
            Haptics.error()
        }
    }

    /// Disconnect a Google account, revoke tokens, and remove it from the app.
    func disconnect(_ account: GoogleAccount) async {
        do {
            try await GoogleAuthService.shared.revoke(accountID: account.id)
        } catch {
            // Proceed with local deletion even if revocation fails.
        }
        modelContainer.mainContext.delete(account)
        save()
        fetchAccounts()
        Haptics.light()
    }

    /// Refresh account list from SwiftData.
    func fetchAccounts() {
        let descriptor = FetchDescriptor<GoogleAccount>(sortBy: [SortDescriptor(\.email)])
        do {
            accounts = try modelContainer.mainContext.fetch(descriptor)
        } catch {
            accounts = []
        }
    }

    private func save() {
        do {
            try modelContainer.mainContext.save()
        } catch {
            lastError = "Failed to save account: \(error.localizedDescription)"
        }
    }
}

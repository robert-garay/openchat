import SwiftUI

struct GoogleAccountSettingsView: View {
    @Environment(GoogleAccountStore.self) private var store

    var body: some View {
        List {
            Section {
                Label {
                    Text(
                        "Connecting a Google account lets agents use your Google Calendar, Gmail, and Google Drive "
                        + "context in chat. Data is sent to the AI providers you configure; OpenChat has no backend for this data."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.orange)
                }
            }

            if !store.isConfigured {
                Section {
                    Label {
                        Text(
                            "Google OAuth is not configured. Set GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_REDIRECT_URI "
                            + "in Config/Local.xcconfig to enable sign-in."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Button {
                    Task { await store.signIn() }
                } label: {
                    HStack {
                        Image(systemName: "g.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        Text(store.isConfigured ? "Connect Google Account" : "Google sign-in unavailable")
                        Spacer()
                        if store.isSigningIn {
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isSigningIn || !store.isConfigured)
            }

            if !store.accounts.isEmpty {
                ForEach(store.accounts) { account in
                    AccountSection(account: account)
                }
            }

            if let error = store.lastError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("Google Account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.fetchAccounts()
        }
    }
}

private struct AccountSection: View {
    let account: GoogleAccount
    @Environment(GoogleAccountStore.self) private var store

    var body: some View {
        Section {
            HStack(spacing: 12) {
                if let pictureURL = account.pictureURL {
                    AsyncImage(url: pictureURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name ?? account.email)
                        .font(.headline)
                    Text(account.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            ForEach(GoogleApp.allCases) { app in
                Toggle(isOn: Binding(
                    get: { store.isEnabled(app, for: account) },
                    set: { store.setEnabled($0, app: app, for: account) }
                )) {
                    HStack(spacing: 12) {
                        Image(systemName: app.symbolName)
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.title)
                            Text(app.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .disabled(!account.isConnected(to: app))
            }

            Button(role: .destructive) {
                Task { await store.disconnect(account) }
            } label: {
                Label("Disconnect", systemImage: "xmark.circle.fill")
            }
        } header: {
            Text("Connected account")
        } footer: {
            Text(
                "Toggle each app to include or exclude its data from chat context. "
                + "Disconnecting removes the account and deletes stored tokens from this device."
            )
        }
    }
}

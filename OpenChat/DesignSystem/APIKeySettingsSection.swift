import SwiftUI

/// Shared API-key controls for provider settings: empty state with field +
/// save action, or a saved state with redacted preview, replace, and remove.
struct APIKeySettingsSection: View {
    let placeholder: String
    let redactedKey: String?
    @Binding var draftKey: String
    var helpURL: URL? = nil
    var helpProviderName: String? = nil
    var allowsRemove: Bool = true
    var onSave: () -> Void
    var onRequestReplace: () -> Void
    var onRequestRemove: (() -> Void)? = nil

    @FocusState private var fieldFocused: Bool

    private var canSave: Bool {
        !draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Section {
            if let redactedKey {
                savedKeyRow(redactedKey)

                Button(action: onRequestReplace) {
                    Label("Replace Key", systemImage: "arrow.triangle.2.circlepath")
                }

                if allowsRemove, let onRequestRemove {
                    Button(role: .destructive, action: onRequestRemove) {
                        Label("Remove Key", systemImage: "trash")
                    }
                }
            } else {
                SecureField(placeholder, text: $draftKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($fieldFocused)

                Button(action: onSave) {
                    Label("Save Key", systemImage: "key.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
                .accessibilityHint(canSave ? "Saves the API key to the Keychain" : "Enter an API key first")
            }
        } header: {
            Text("API Key")
        } footer: {
            if let helpURL, let helpProviderName {
                Link("Get an API key from \(helpProviderName) →", destination: helpURL)
            }
        }
        .onAppear {
            if redactedKey == nil {
                fieldFocused = true
            }
        }
    }

    private func savedKeyRow(_ redacted: String) -> some View {
        Button(action: onRequestReplace) {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Text(redacted)
                    .font(.body.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("API key")
        .accessibilityValue(redacted)
        .accessibilityHint("Double tap to replace key")
    }
}

/// Centered modal overlay for replacing a stored API key.
struct APIKeyReplaceDialog: View {
    let placeholder: String
    @Binding var draftKey: String
    var onCancel: () -> Void
    var onSave: () -> Void

    @FocusState private var fieldFocused: Bool

    private var canSave: Bool {
        !draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SettingsModalChrome(onDismiss: onCancel) {
            SecureField(placeholder, text: $draftKey)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(
                    Color(.secondarySystemFill),
                    in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                )
                .focused($fieldFocused)

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Button(action: onSave) {
                    Label("Save", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!canSave)
            }
        }
        .onAppear { fieldFocused = true }
    }
}

/// Centered confirm/cancel dialog used instead of bottom `confirmationDialog` sheets.
struct SettingsConfirmDialog: View {
    let title: String
    let message: String
    var confirmTitle: String = "Remove"
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        SettingsModalChrome(onDismiss: onCancel) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Button(confirmTitle, role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Shared dimmed backdrop + material card used by settings center modals.
private struct SettingsModalChrome<Content: View>: View {
    var onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 16) {
                content()
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            .padding(.horizontal, 24)
        }
    }
}

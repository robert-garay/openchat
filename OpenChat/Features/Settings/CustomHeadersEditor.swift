import SwiftUI

/// One editable row in the custom-headers editor.
struct CustomHeaderEntry: Identifiable, Equatable {
    let id: UUID
    var name: String
    var value: String
    var isValueRevealed: Bool = false

    init(id: UUID = UUID(), name: String = "", value: String = "", isValueRevealed: Bool = false) {
        self.id = id
        self.name = name
        self.value = value
        self.isValueRevealed = isValueRevealed
    }
}

extension Array where Element == CustomHeaderEntry {
    /// Trimmed headers sanitized for wire use. Later duplicate names win.
    var headerDictionary: [String: String] {
        let raw = reduce(into: [:]) { result, entry in
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            result[name] = entry.value
        }
        return ProviderHTTPHeaders.sanitizeCustomHeaders(raw)
    }
}

extension CustomHeaderEntry {
    static func list(from dictionary: [String: String]) -> [CustomHeaderEntry] {
        dictionary.keys.sorted().map {
            CustomHeaderEntry(name: $0, value: dictionary[$0] ?? "")
        }
    }
}

/// Editable extra HTTP headers for a provider. Used when a gateway requires
/// transport headers that are not part of the API key (for example OpenCode's
/// `x-opencode-session`).
struct CustomHeadersEditor: View {
    @Binding var headers: [CustomHeaderEntry]
    var startsExpanded: Bool = false

    @State private var isExpanded: Bool

    init(headers: Binding<[CustomHeaderEntry]>, startsExpanded: Bool = false) {
        _headers = headers
        self.startsExpanded = startsExpanded
        _isExpanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                if headers.isEmpty {
                    Text("No custom headers configured.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach($headers) { $header in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Header name", text: $header.name)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        HStack(spacing: 8) {
                            Group {
                                if header.isValueRevealed {
                                    TextField("Header value", text: $header.value)
                                } else {
                                    SecureField("Header value", text: $header.value)
                                }
                            }
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            Button {
                                header.isValueRevealed.toggle()
                            } label: {
                                Image(systemName: header.isValueRevealed ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(header.isValueRevealed ? "Hide header value" : "Show header value")
                        }
                        if ProviderHTTPHeaders.isReservedHeaderName(header.name) {
                            Text("This header name is reserved and will not be sent.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if !header.name.isEmpty, !ProviderHTTPHeaders.isValidHeaderName(header.name) {
                            Text("Header name contains invalid characters.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .onDelete { headers.remove(atOffsets: $0) }

                Button {
                    headers.append(CustomHeaderEntry())
                } label: {
                    Label("Add Header", systemImage: "plus.circle.fill")
                }
            } label: {
                Text("Advanced")
            }
        } footer: {
            Text("Optional HTTP headers sent with every request to this provider. Values are stored in the Keychain. Keep API keys in the API key field.")
        }
    }
}

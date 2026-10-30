import SwiftUI

/// One editable row in the custom-headers editor.
struct CustomHeaderEntry: Identifiable, Equatable {
    let id: UUID
    var name: String
    var value: String

    init(id: UUID = UUID(), name: String = "", value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }
}

extension Array where Element == CustomHeaderEntry {
    /// Trimmed, non-empty headers. Later duplicate names win.
    var headerDictionary: [String: String] {
        reduce(into: [:]) { result, entry in
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            result[name] = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
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

    var body: some View {
        Section {
            ForEach($headers) { $header in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Header name", text: $header.name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Header value", text: $header.value)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .onDelete { headers.remove(atOffsets: $0) }

            Button {
                headers.append(CustomHeaderEntry())
            } label: {
                Label("Add Header", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Custom Headers")
        } footer: {
            Text("Sent with every request to this provider. Use this for required transport headers such as x-opencode-session; keep API keys in the API key field.")
        }
    }
}

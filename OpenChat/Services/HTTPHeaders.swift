import Foundation

/// Validation and application of user-defined provider HTTP headers.
enum ProviderHTTPHeaders {
    static let openChatProductName = "OpenChat"

    private static let reservedHeaderNames: Set<String> = [
        "authorization",
        "x-api-key",
        "anthropic-version",
        "host",
        "content-type",
        "content-length",
        "connection",
        "cookie",
        "transfer-encoding",
    ]

    /// RFC 9110 `token` characters for header field names. These are ASCII
    /// only, so non-ASCII lookalikes (for example a Cyrillic "Аuthorization")
    /// cannot slip past the reserved-name check.
    private static let tokenCharacterSet: CharacterSet = {
        var set = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~")
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        set.insert(charactersIn: "0123456789")
        return set
    }()

    static func isReservedHeaderName(_ rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return true }
        if reservedHeaderNames.contains(name) { return true }
        if name.hasPrefix("proxy-") { return true }
        return false
    }

    static func isValidHeaderName(_ rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return name.unicodeScalars.allSatisfy { tokenCharacterSet.contains($0) }
    }

    /// Drops invalid/reserved names and strips control characters from values.
    static func sanitizeCustomHeaders(_ headers: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (rawName, rawValue) in headers {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidHeaderName(name), !isReservedHeaderName(name) else { continue }
            let value = sanitizeHeaderValue(rawValue)
            guard !value.isEmpty else { continue }
            result[name] = value
        }
        return result
    }

    static func sanitizeHeaderValue(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
    }

    /// Merges stored headers with OpenCode session injection and default client id.
    static func effectiveHeaders(
        stored: [String: String],
        template: ProviderTemplate?,
        providerID: String,
        conversationID: UUID?
    ) -> [String: String] {
        var headers = sanitizeCustomHeaders(stored)
        if template?.injectsOpenCodeSession == true {
            let session: String
            if let conversationID {
                session = "openchat-\(conversationID.uuidString)"
            } else {
                session = "openchat-catalog-\(providerID)"
            }
            headers["x-opencode-session"] = session
        }
        if template?.sendsOpenCodeClientHeader == true, headers["x-opencode-client"] == nil {
            headers["x-opencode-client"] = "openchat"
        }
        return headers
    }

    static func openChatUserAgent() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(openChatProductName)/\(version) (\(build))"
    }

    static func keychainAccount(forProviderID providerID: String) -> String {
        "customHeaders.\(providerID)"
    }

    static func loadFromKeychain(providerID: String) -> [String: String] {
        guard let json = KeychainStore.get(keychainAccount(forProviderID: providerID)),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return sanitizeCustomHeaders(decoded)
    }

    static func saveToKeychain(_ headers: [String: String], providerID: String) {
        let sanitized = sanitizeCustomHeaders(headers)
        if sanitized.isEmpty {
            KeychainStore.remove(keychainAccount(forProviderID: providerID))
            return
        }
        guard let data = try? JSONEncoder().encode(sanitized),
              let json = String(data: data, encoding: .utf8)
        else { return }
        KeychainStore.set(json, forKey: keychainAccount(forProviderID: providerID))
    }

    static func removeFromKeychain(providerID: String) {
        KeychainStore.remove(keychainAccount(forProviderID: providerID))
    }
}

extension URLRequest {
    /// Apply user-supplied provider headers. Invalid names/values are ignored
    /// rather than producing an unbuildable request.
    mutating func applyCustomHeaders(_ headers: [String: String]) {
        for (name, value) in ProviderHTTPHeaders.sanitizeCustomHeaders(headers) {
            setValue(value, forHTTPHeaderField: name)
        }
    }

    /// Call after auth headers are set so credentials cannot be overridden.
    mutating func applyOpenChatUserAgent() {
        setValue(ProviderHTTPHeaders.openChatUserAgent(), forHTTPHeaderField: "User-Agent")
    }
}

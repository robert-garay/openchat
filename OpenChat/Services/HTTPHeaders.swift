import Foundation

extension URLRequest {
    /// Apply user-supplied provider headers. Invalid names/values are ignored
    /// rather than producing an unbuildable request.
    mutating func applyCustomHeaders(_ headers: [String: String]) {
        for (rawName, rawValue) in headers {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  !name.contains(where: { $0.isNewline }),
                  !value.contains(where: { $0.isNewline }) else {
                continue
            }
            setValue(value, forHTTPHeaderField: name)
        }
    }
}

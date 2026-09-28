import Foundation

/// Where chat completions run for a configured provider.
enum InferenceBackend: String, Codable, Hashable, Sendable {
    case remoteHTTP
    case localMLX
}

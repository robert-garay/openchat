import Foundation

/// A provider-agnostic representation of one turn in the conversation,
/// built from `ChatMessage` right before it's sent over the network.
struct ChatTurn: Sendable {
    var role: MessageRole
    var content: String
    var images: [ChatImageAttachment]

    init(role: MessageRole, content: String, images: [ChatImageAttachment] = []) {
        self.role = role
        self.content = content
        self.images = images
    }

    var hasImages: Bool { !images.isEmpty }
}

enum ChatServiceError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case http(status: Int, body: String)
    case decoding(String)
    case cancelled
    case modelLacksVision

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key configured for this provider."
        case .invalidURL:
            return "The provider's base URL is invalid."
        case .http(let status, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Request failed with status \(status)."
            }
            return "Request failed (\(status)): \(trimmed)"
        case .decoding(let reason):
            return "Couldn't read the response: \(reason)"
        case .cancelled:
            return "Request cancelled."
        case .modelLacksVision:
            return "This model can't process images. Choose a vision-capable model."
        }
    }
}

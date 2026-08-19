import Foundation

/// A provider-agnostic representation of one turn in the conversation,
/// built from `ChatMessage` right before it's sent over the network.
struct ChatTurn: Sendable {
    var role: MessageRole
    var content: String
    var images: [ChatImageAttachment]
    var documents: [ChatDocumentAttachment]
    /// Assistant turns may request tool calls instead of (or alongside) text.
    var toolCalls: [ChatToolCall]
    /// For `.tool` turns (OpenAI) / tool_result blocks (Anthropic).
    var toolCallID: String?

    init(
        role: MessageRole,
        content: String,
        images: [ChatImageAttachment] = [],
        documents: [ChatDocumentAttachment] = [],
        toolCalls: [ChatToolCall] = [],
        toolCallID: String? = nil
    ) {
        self.role = role
        self.content = content
        self.images = images
        self.documents = documents
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    var hasImages: Bool { !images.isEmpty }
    var hasDocuments: Bool { !documents.isEmpty }
    var hasToolCalls: Bool { !toolCalls.isEmpty }
}

enum ChatServiceError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case http(status: Int, body: String)
    case decoding(String)
    case cancelled
    case timedOut
    case connectionDropped
    case modelLacksVision
    case modelLacksFiles
    case serviceNotConfigured
    case providerOrModelNotFound

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key configured for this provider."
        case .serviceNotConfigured:
            return "Background generation isn't fully configured yet."
        case .providerOrModelNotFound:
            return "The selected provider or model couldn't be found."
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
        case .timedOut:
            return """
            The request timed out before the model finished responding. \
            This often happens with very long prompts, large attachments, or a slow provider. \
            Try again, shorten the conversation (Compact), or remove large images.
            """
        case .connectionDropped:
            return """
            The connection dropped partway through the response. \
            OpenChat tries to reconnect and resume automatically when possible.
            """
        case .modelLacksVision:
            return "This model can't process images. Choose a vision-capable model."
        case .modelLacksFiles:
            return "This model can't process documents. Choose a model marked with a doc icon."
        }
    }

    /// Maps transport / provider failures into a stable string for the chat UI.
    static func userFacingMessage(for error: Error) -> String {
        if let serviceError = error as? ChatServiceError {
            return serviceError.localizedDescription
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return ChatServiceError.timedOut.localizedDescription
        }
        return error.localizedDescription
    }
}

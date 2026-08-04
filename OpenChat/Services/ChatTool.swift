import Foundation

/// Provider-agnostic tool definition passed to models that support function calling.
struct ChatToolDefinition: Equatable, Sendable {
    var name: String
    var description: String
    /// Raw JSON Schema object string for the tool parameters.
    var parametersJSON: String
}

/// A single tool invocation requested by the model.
struct ChatToolCall: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    /// JSON object string of arguments, e.g. `{"query":"..."}`.
    var argumentsJSON: String
}

/// Outcome of one non-streaming completion used during the tool-calling loop.
struct ChatCompletionResult: Equatable, Sendable {
    var text: String
    var toolCalls: [ChatToolCall]
    var images: [ChatImageAttachment]

    init(text: String, toolCalls: [ChatToolCall] = [], images: [ChatImageAttachment] = []) {
        self.text = text
        self.toolCalls = toolCalls
        self.images = images
    }

    var hasToolCalls: Bool { !toolCalls.isEmpty }
    var hasImages: Bool { !images.isEmpty }
}

/// Incremental events from a chat completion (text stream and/or generated images).
enum ChatStreamEvent: Equatable, Sendable {
    case text(String)
    case images([ChatImageAttachment])
}

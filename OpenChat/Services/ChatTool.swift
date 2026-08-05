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
    var reasoning: String
    var toolCalls: [ChatToolCall]
    var images: [ChatImageAttachment]

    init(
        text: String,
        reasoning: String = "",
        toolCalls: [ChatToolCall] = [],
        images: [ChatImageAttachment] = []
    ) {
        self.text = text
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.images = images
    }

    var hasToolCalls: Bool { !toolCalls.isEmpty }
    var hasImages: Bool { !images.isEmpty }
    var hasReasoning: Bool { !reasoning.isEmpty }
}

/// Incremental events from a chat completion (text stream and/or generated images).
enum ChatStreamEvent: Equatable, Sendable {
    case text(String)
    /// Model chain-of-thought / extended thinking (separate from the visible answer).
    case reasoning(String)
    case images([ChatImageAttachment])
}

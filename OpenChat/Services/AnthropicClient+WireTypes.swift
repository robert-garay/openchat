import Foundation

// MARK: - Tool-call accumulation

struct AnthropicToolCallAccumulator {
    private var blockTypes: [Int: String] = [:]
    private var callsByIndex: [Int: AnthropicAccumulatingToolCall] = [:]

    var isEmpty: Bool { callsByIndex.isEmpty }

    mutating func startBlock(index: Int, type: String, id: String?, name: String?) {
        blockTypes[index] = type
        if type == "tool_use" {
            callsByIndex[index, default: AnthropicAccumulatingToolCall()].id = id ?? ""
            callsByIndex[index, default: AnthropicAccumulatingToolCall()].name = name ?? ""
        }
    }

    func isToolUse(at index: Int) -> Bool {
        blockTypes[index] == "tool_use"
    }

    mutating func appendDelta(index: Int, delta: AnthropicStreamEvent.Delta) {
        guard delta.type == "input_json_delta", let partialJson = delta.partialJson else { return }
        callsByIndex[index, default: AnthropicAccumulatingToolCall()].arguments += partialJson
    }

    var toolCalls: [ChatToolCall] {
        callsByIndex
            .sorted { $0.key < $1.key }
            .compactMap { $0.value.chatToolCall }
    }
}

struct AnthropicAccumulatingToolCall {
    var id: String = ""
    var name: String = ""
    var arguments: String = ""

    var chatToolCall: ChatToolCall? {
        guard !id.isEmpty, !name.isEmpty else { return nil }
        return ChatToolCall(
            id: id,
            name: name,
            argumentsJSON: arguments.isEmpty ? "{}" : arguments
        )
    }
}

// MARK: - Wire types

struct AnthropicRequestBody: Encodable {
    var model: String
    var maxTokens: Int
    var system: String?
    var messages: [AnthropicRequestMessage]
    var stream: Bool
    var tools: [AnthropicToolPayload]?
    var thinking: AnthropicThinkingPayload?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, stream, tools, thinking
        case maxTokens = "max_tokens"
    }
}

struct AnthropicThinkingPayload: Encodable {
    var type: String
    var budgetTokens: Int

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }
}

struct AnthropicRequestMessage: Encodable {
    var role: String
    var content: AnthropicMessageContent
}

enum AnthropicMessageContent: Encodable {
    case text(String)
    case blocks([AnthropicContentBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value):
            try container.encode(value)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }
}

enum AnthropicContentBlock: Encodable {
    case text(String)
    case image(mediaType: String, data: String)
    case toolUse(id: String, name: String, input: AnyCodableJSON)
    case toolResult(toolUseID: String, content: String)

    enum CodingKeys: String, CodingKey {
        case type, text, source, id, name, input, content
        case toolUseID = "tool_use_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let mediaType, let data):
            try container.encode("image", forKey: .type)
            try container.encode(
                ["type": "base64", "media_type": mediaType, "data": data],
                forKey: .source
            )
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseID, let content):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseID, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
        }
    }
}

struct AnthropicToolPayload: Encodable {
    var name: String
    var description: String
    var inputSchema: AnyCodableJSON

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

struct AnthropicMessagesResponse: Decodable {
    var content: [ContentBlock]?

    struct ContentBlock: Decodable {
        var type: String
        var text: String?
        var id: String?
        var name: String?
        var input: AnyCodableJSON?
    }
}

struct AnthropicStreamEvent: Decodable {
    struct Delta: Decodable {
        var type: String?
        var text: String?
        var partialJson: String?

        enum CodingKeys: String, CodingKey {
            case type, text
            case partialJson = "partial_json"
        }
    }
    struct ContentBlock: Decodable {
        var type: String?
        var id: String?
        var name: String?
    }
    var type: String
    var delta: Delta?
    var index: Int?
    var contentBlock: ContentBlock?

    enum CodingKeys: String, CodingKey {
        case type, delta, index
        case contentBlock = "content_block"
    }
}

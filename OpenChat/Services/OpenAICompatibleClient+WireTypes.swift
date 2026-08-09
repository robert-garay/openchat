import Foundation

// MARK: - Tool-call accumulation

struct OpenAIToolCallAccumulator {
    private var callsByIndex: [Int: OpenAIAccumulatingToolCall] = [:]

    var isEmpty: Bool { callsByIndex.isEmpty }

    mutating func append(_ deltas: [OpenAIToolCallDeltaDTO]) {
        for delta in deltas {
            callsByIndex[delta.index, default: OpenAIAccumulatingToolCall()].append(delta)
        }
    }

    var toolCalls: [ChatToolCall] {
        callsByIndex
            .sorted { $0.key < $1.key }
            .compactMap { $0.value.chatToolCall }
    }
}

struct OpenAIAccumulatingToolCall {
    var id: String = ""
    var name: String = ""
    var arguments: String = ""

    mutating func append(_ delta: OpenAIToolCallDeltaDTO) {
        if let id = delta.id, !id.isEmpty { self.id = id }
        if let name = delta.function?.name, !name.isEmpty { self.name = name }
        if let arguments = delta.function?.arguments { self.arguments += arguments }
    }

    var chatToolCall: ChatToolCall? {
        guard !id.isEmpty, !name.isEmpty else { return nil }
        return ChatToolCall(
            id: id,
            name: name,
            argumentsJSON: arguments.isEmpty ? "{}" : arguments
        )
    }
}

// MARK: - Request body builder

func makeOpenAICompatibleRequestBody(
    model: String,
    messages: [OpenAIRequestMessage],
    stream: Bool,
    tools: [OpenAIToolPayload]?,
    modalities: [String]?,
    effort: EffortLevel?,
    reasoningEnabled: Bool?,
    baseURL: String
) -> OpenAIRequestBody {
    let isDeepSeek = baseURL.lowercased().contains("deepseek")
    if isDeepSeek {
        let thinking: OpenAIDeepSeekThinkingPayload? = (reasoningEnabled == true)
            ? OpenAIDeepSeekThinkingPayload(type: "enabled")
            : nil
        return OpenAIRequestBody(
            model: model,
            messages: messages,
            stream: stream,
            tools: tools,
            modalities: modalities,
            reasoningEffort: nil,
            reasoning: nil,
            thinking: thinking
        )
    }
    return OpenAIRequestBody(
        model: model,
        messages: messages,
        stream: stream,
        tools: tools,
        modalities: modalities,
        reasoningEffort: effort?.rawValue,
        reasoning: reasoningEnabled.map { OpenAIReasoningPayload(enabled: $0) },
        thinking: nil
    )
}

// MARK: - Wire types

struct OpenAIRequestBody: Encodable {
    var model: String
    var messages: [OpenAIRequestMessage]
    var stream: Bool
    var tools: [OpenAIToolPayload]?
    var modalities: [String]?
    var reasoningEffort: String?
    var reasoning: OpenAIReasoningPayload?
    var thinking: OpenAIDeepSeekThinkingPayload?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, tools, modalities
        case reasoningEffort = "reasoning_effort"
        case reasoning
        case thinking
    }
}

struct OpenAIReasoningPayload: Encodable {
    var enabled: Bool
}

struct OpenAIDeepSeekThinkingPayload: Encodable {
    var type: String
}

struct OpenAIRequestMessage: Encodable {
    var role: String
    var content: OpenAIMessageContent
    var toolCallID: String?
    var toolCalls: [OpenAIToolCallPayload]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }
}

enum OpenAIMessageContent: Encodable {
    case text(String)
    case parts([MultimodalRequestEncoder.OpenAIPart])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value):
            try container.encode(value)
        case .parts(let parts):
            try container.encode(parts)
        case .null:
            try container.encodeNil()
        }
    }
}

struct OpenAIToolPayload: Encodable {
    var type: String
    var function: FunctionPayload

    struct FunctionPayload: Encodable {
        var name: String
        var description: String
        var parameters: AnyCodableJSON
    }
}

struct OpenAIToolCallPayload: Encodable {
    var id: String
    var type: String
    var function: FunctionArgs

    struct FunctionArgs: Encodable {
        var name: String
        var arguments: String
    }
}

struct OpenAICompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: OpenAIFlexibleMessageContent
            var toolCalls: [OpenAIToolCallDTO]?
            var images: [OpenAIGeneratedImageDTO]?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if container.contains(.content),
                   (try? container.decodeNil(forKey: .content)) != true {
                    content = try container.decode(OpenAIFlexibleMessageContent.self, forKey: .content)
                } else {
                    content = OpenAIFlexibleMessageContent()
                }
                toolCalls = try container.decodeIfPresent([OpenAIToolCallDTO].self, forKey: .toolCalls)
                images = try container.decodeIfPresent([OpenAIGeneratedImageDTO].self, forKey: .images)
            }

            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
                case images
            }
        }
        var message: Message?
    }
    var choices: [Choice]?
}

struct OpenAIToolCallDTO: Decodable {
    var id: String?
    var function: FunctionDTO?

    struct FunctionDTO: Decodable {
        var name: String?
        var arguments: String?
    }
}

struct OpenAIGeneratedImageDTO: Decodable {
    var type: String?
    var imageURL: ImageURLDTO?

    enum CodingKeys: String, CodingKey {
        case type
        case imageURL = "image_url"
    }

    struct ImageURLDTO: Decodable {
        var url: String?
    }
}

/// Assistant `content` may be a plain string or a multimodal part array.
struct OpenAIFlexibleMessageContent: Decodable {
    var text: String
    var inlineImages: [ChatImageAttachment]

    init(text: String = "", inlineImages: [ChatImageAttachment] = []) {
        self.text = text
        self.inlineImages = inlineImages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.init()
            return
        }
        if let string = try? container.decode(String.self) {
            self.init(text: string)
            return
        }
        let parts = try container.decode([OpenAIContentPartDTO].self)
        var textParts: [String] = []
        var images: [ChatImageAttachment] = []
        for part in parts {
            if let partText = part.text, !partText.isEmpty {
                textParts.append(partText)
            }
            if let url = part.imageURL?.url,
               let attachment = GeneratedImageParser.attachment(fromDataURI: url) {
                images.append(attachment)
            }
        }
        self.init(text: textParts.joined(), inlineImages: images)
    }

    private struct OpenAIContentPartDTO: Decodable {
        var type: String?
        var text: String?
        var imageURL: OpenAIGeneratedImageDTO.ImageURLDTO?

        enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }
    }
}

struct OpenAIChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            var content: OpenAIFlexibleMessageContent
            var images: [OpenAIGeneratedImageDTO]?
            var toolCalls: [OpenAIToolCallDeltaDTO]?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if container.contains(.content),
                   (try? container.decodeNil(forKey: .content)) != true {
                    content = try container.decode(OpenAIFlexibleMessageContent.self, forKey: .content)
                } else {
                    content = OpenAIFlexibleMessageContent()
                }
                images = try container.decodeIfPresent([OpenAIGeneratedImageDTO].self, forKey: .images)
                toolCalls = try container.decodeIfPresent([OpenAIToolCallDeltaDTO].self, forKey: .toolCalls)
            }

            enum CodingKeys: String, CodingKey {
                case content, images
                case toolCalls = "tool_calls"
            }
        }
        var delta: Delta?
    }
    var choices: [Choice]?
}

/// A single fragment of a tool call as it arrives in a streaming chunk.
struct OpenAIToolCallDeltaDTO: Decodable {
    var index: Int
    var id: String?
    var type: String?
    var function: FunctionDeltaDTO?

    struct FunctionDeltaDTO: Decodable {
        var name: String?
        var arguments: String?
    }
}

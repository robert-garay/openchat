import Foundation

/// Shared multimodal request shaping for OpenAI-compatible and Anthropic wire formats.
enum MultimodalRequestEncoder {
    struct OpenAIPart: Encodable, Equatable {
        var type: String
        var text: String?
        var imageURL: ImageURL?

        enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }

        struct ImageURL: Encodable, Equatable {
            var url: String
        }
    }

    struct AnthropicPart: Encodable, Equatable {
        var type: String
        var text: String?
        var source: ImageSource?

        struct ImageSource: Encodable, Equatable {
            var type = "base64"
            var mediaType: String
            var data: String

            enum CodingKeys: String, CodingKey {
                case type, data
                case mediaType = "media_type"
            }
        }
    }

    static func openAIParts(for turn: ChatTurn) -> [OpenAIPart]? {
        guard turn.hasImages else { return nil }
        var parts: [OpenAIPart] = turn.images.map {
            OpenAIPart(type: "image_url", text: nil, imageURL: .init(url: $0.dataURI))
        }
        let trimmed = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(OpenAIPart(type: "text", text: trimmed, imageURL: nil))
        }
        return parts
    }

    static func anthropicParts(for turn: ChatTurn) -> [AnthropicPart]? {
        guard turn.hasImages else { return nil }
        var parts: [AnthropicPart] = turn.images.map {
            AnthropicPart(
                type: "image",
                text: nil,
                source: .init(mediaType: $0.mimeType, data: $0.data.base64EncodedString())
            )
        }
        let trimmed = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(AnthropicPart(type: "text", text: trimmed, source: nil))
        } else if parts.isEmpty {
            parts.append(AnthropicPart(type: "text", text: "", source: nil))
        }
        return parts
    }
}

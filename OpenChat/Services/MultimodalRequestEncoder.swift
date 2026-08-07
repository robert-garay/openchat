import Foundation

/// Shared multimodal request shaping for OpenAI-compatible and Anthropic wire formats.
enum MultimodalRequestEncoder {
    struct Base64Source: Encodable, Equatable {
        var type = "base64"
        var mediaType: String
        var data: String

        enum CodingKeys: String, CodingKey {
            case type, data
            case mediaType = "media_type"
        }
    }

    struct OpenAIPart: Encodable, Equatable {
        var type: String
        var text: String?
        var imageURL: ImageURL?
        var file: FileData?

        enum CodingKeys: String, CodingKey {
            case type, text, file
            case imageURL = "image_url"
        }

        struct ImageURL: Encodable, Equatable {
            var url: String
        }

        struct FileData: Encodable, Equatable {
            var filename: String
            var fileData: String

            enum CodingKeys: String, CodingKey {
                case filename
                case fileData = "file_data"
            }
        }
    }

    struct AnthropicPart: Encodable, Equatable {
        var type: String
        var text: String?
        var source: Base64Source?
    }

    static func openAIParts(for turn: ChatTurn) -> [OpenAIPart]? {
        guard turn.hasImages || turn.hasDocuments else { return nil }
        var parts: [OpenAIPart] = turn.documents.map {
            OpenAIPart(type: "file", text: nil, imageURL: nil, file: .init(filename: $0.filename, fileData: $0.dataURI))
        }
        parts.append(contentsOf: turn.images.map {
            OpenAIPart(type: "image_url", text: nil, imageURL: .init(url: $0.dataURI), file: nil)
        })
        let trimmed = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(OpenAIPart(type: "text", text: trimmed, imageURL: nil, file: nil))
        }
        return parts
    }

    static func anthropicParts(for turn: ChatTurn) -> [AnthropicPart]? {
        guard turn.hasImages || turn.hasDocuments else { return nil }
        var parts: [AnthropicPart] = turn.documents.map {
            AnthropicPart(
                type: "document",
                text: nil,
                source: .init(mediaType: $0.mimeType, data: $0.data.base64EncodedString())
            )
        }
        parts.append(contentsOf: turn.images.map {
            AnthropicPart(
                type: "image",
                text: nil,
                source: .init(mediaType: $0.mimeType, data: $0.data.base64EncodedString())
            )
        })
        let trimmed = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(AnthropicPart(type: "text", text: trimmed, source: nil))
        } else if parts.isEmpty {
            parts.append(AnthropicPart(type: "text", text: "", source: nil))
        }
        return parts
    }
}

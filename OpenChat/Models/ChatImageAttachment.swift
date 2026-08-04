import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// An image on a chat turn — user upload or model-generated output.
struct ChatImageAttachment: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var mimeType: String
    var data: Data

    init(id: UUID = UUID(), mimeType: String, data: Data) {
        self.id = id
        self.mimeType = mimeType
        self.data = data
    }

    var dataURI: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}

/// Parses provider image payloads (OpenRouter `images[]`, data URIs, markdown embeds).
enum GeneratedImageParser {
    /// `data:image/png;base64,...` → attachment. Returns nil for http(s) URLs or invalid data.
    static func attachment(fromDataURI string: String) -> ChatImageAttachment? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("data:") else { return nil }
        guard let comma = trimmed.firstIndex(of: ",") else { return nil }

        let metaStart = trimmed.index(trimmed.startIndex, offsetBy: 5)
        let meta = trimmed[metaStart..<comma]
        let payload = String(trimmed[trimmed.index(after: comma)...])
        guard !payload.isEmpty else { return nil }

        let metaLower = meta.lowercased()
        let mime = meta.split(separator: ";").first.map(String.init)?.lowercased() ?? "image/png"
        let normalizedMIME = mime.hasPrefix("image/") ? mime : "image/png"

        let data: Data?
        if metaLower.contains("base64") {
            data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
        } else if let decoded = payload.removingPercentEncoding {
            data = Data(decoded.utf8)
        } else {
            data = nil
        }
        guard let data, !data.isEmpty else { return nil }
        return ChatImageAttachment(mimeType: normalizedMIME, data: data)
    }

    /// Pulls `![](data:image/...;base64,...)` embeds out of markdown, returning cleaned text + images.
    static func extractMarkdownDataURIImages(from text: String) -> (text: String, images: [ChatImageAttachment]) {
        guard text.contains("data:image") else { return (text, []) }

        let pattern = #"!\[[^\]]*\]\((data:image\/[a-zA-Z0-9.+-]+;base64,[A-Za-z0-9+/=\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (text, [])
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else { return (text, []) }

        var images: [ChatImageAttachment] = []
        for match in matches {
            guard match.numberOfRanges >= 2,
                  let uriRange = Range(match.range(at: 1), in: text)
            else { continue }
            let uri = String(text[uriRange])
                .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            if let attachment = attachment(fromDataURI: uri) {
                images.append(attachment)
            }
        }

        var cleaned = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: cleaned) else { continue }
            cleaned.replaceSubrange(fullRange, with: "")
        }
        cleaned = cleaned
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (cleaned, images)
    }
}

enum ImageAttachmentEncoder {
    /// Downscales and JPEG-encodes image bytes so vision requests stay within typical provider limits.
    static func makeAttachment(from imageData: Data, maxDimension: CGFloat = 1536, quality: CGFloat = 0.72) -> ChatImageAttachment? {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData) else { return nil }
        return makeAttachment(from: image, maxDimension: maxDimension, quality: quality)
        #else
        return ChatImageAttachment(mimeType: "image/jpeg", data: imageData)
        #endif
    }

    #if canImport(UIKit)
    static func makeAttachment(from image: UIImage, maxDimension: CGFloat = 1536, quality: CGFloat = 0.72) -> ChatImageAttachment? {
        let scaled = scaledImage(image, maxDimension: maxDimension)
        guard let data = scaled.jpegData(compressionQuality: quality), !data.isEmpty else { return nil }
        return ChatImageAttachment(mimeType: "image/jpeg", data: data)
    }

    private static func scaledImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    #endif
}

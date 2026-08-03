import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// An image the user attached to a chat turn (composer pending or persisted message).
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

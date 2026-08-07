import Foundation

/// A PDF document on a chat turn — user-uploaded, for models that can read files.
struct ChatDocumentAttachment: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var filename: String
    var mimeType: String
    var data: Data

    init(id: UUID = UUID(), filename: String, mimeType: String, data: Data) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }

    var dataURI: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}

enum DocumentAttachmentEncoder {
    /// Anthropic & OpenAI PDF cap.
    static let maxByteCount = 32 * 1024 * 1024

    private static let pdfMagicBytes: [UInt8] = [0x25, 0x50, 0x44, 0x46] // "%PDF"

    static func makeAttachment(from data: Data, filename: String) -> ChatDocumentAttachment? {
        guard data.count <= maxByteCount, data.starts(with: pdfMagicBytes) else { return nil }
        return ChatDocumentAttachment(filename: filename, mimeType: "application/pdf", data: data)
    }
}

import XCTest
@testable import OpenChat

final class DocumentAttachmentTests: XCTestCase {
    private let pdfHeader = Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]) // "%PDF-1.4"

    func testChatDocumentAttachmentRoundTrip() throws {
        let original = ChatDocumentAttachment(filename: "report.pdf", mimeType: "application/pdf", data: pdfHeader)
        let encoded = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([ChatDocumentAttachment].self, from: encoded)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].filename, "report.pdf")
        XCTAssertEqual(decoded[0].mimeType, "application/pdf")
        XCTAssertEqual(decoded[0].data, original.data)
        XCTAssertTrue(decoded[0].dataURI.hasPrefix("data:application/pdf;base64,"))
    }

    func testDocumentAttachmentEncoderAcceptsValidPDF() {
        let attachment = DocumentAttachmentEncoder.makeAttachment(from: pdfHeader, filename: "notes.pdf")
        XCTAssertNotNil(attachment)
        XCTAssertEqual(attachment?.filename, "notes.pdf")
        XCTAssertEqual(attachment?.mimeType, "application/pdf")
        XCTAssertEqual(attachment?.data, pdfHeader)
    }

    func testDocumentAttachmentEncoderRejectsNonPDF() {
        let notPDF = Data([0x50, 0x4B, 0x03, 0x04]) // ZIP magic bytes
        XCTAssertNil(DocumentAttachmentEncoder.makeAttachment(from: notPDF, filename: "fake.pdf"))
    }

    func testDocumentAttachmentEncoderRejectsOversized() {
        var oversized = Data([0x25, 0x50, 0x44, 0x46])
        oversized.append(Data(count: DocumentAttachmentEncoder.maxByteCount))
        XCTAssertNil(DocumentAttachmentEncoder.makeAttachment(from: oversized, filename: "huge.pdf"))
    }

    func testChatMessageStoresDocumentAttachments() {
        let document = ChatDocumentAttachment(filename: "spec.pdf", mimeType: "application/pdf", data: pdfHeader)
        let message = ChatMessage(role: .user, content: "review this", documentAttachments: [document])
        XCTAssertEqual(message.documentAttachments.count, 1)
        XCTAssertEqual(message.documentAttachments[0].filename, "spec.pdf")
        message.documentAttachments = []
        XCTAssertNil(message.documentAttachmentsData)
    }

    func testChatTurnHasDocuments() {
        let document = ChatDocumentAttachment(filename: "a.pdf", mimeType: "application/pdf", data: pdfHeader)
        let turn = ChatTurn(role: .user, content: "check", documents: [document])
        XCTAssertTrue(turn.hasDocuments)
        XCTAssertFalse(ChatTurn(role: .user, content: "hi").hasDocuments)
    }

    func testFilesCapabilityErrorMessage() {
        let message = ChatServiceError.modelLacksFiles.errorDescription
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.localizedCaseInsensitiveContains("document") == true)
    }

    func testAIModelSupportsFiles() {
        let withFiles = AIModel(id: "m1", displayName: "M1", capabilities: [.files])
        let withoutFiles = AIModel(id: "m2", displayName: "M2", capabilities: [.vision])
        XCTAssertTrue(withFiles.supportsFiles)
        XCTAssertFalse(withoutFiles.supportsFiles)
    }

    func testOpenAIMultimodalPartsIncludeDocumentOnly() throws {
        let document = ChatDocumentAttachment(filename: "spec.pdf", mimeType: "application/pdf", data: pdfHeader)
        let turn = ChatTurn(role: .user, content: "Summarize this", documents: [document])
        let parts = MultimodalRequestEncoder.openAIParts(for: turn)
        XCTAssertEqual(parts?.count, 2)
        XCTAssertEqual(parts?[0].type, "file")
        XCTAssertEqual(parts?[0].file?.filename, "spec.pdf")
        XCTAssertEqual(parts?[0].file?.fileData, document.dataURI)
        XCTAssertEqual(parts?[1].type, "text")
        XCTAssertEqual(parts?[1].text, "Summarize this")
    }

    func testAnthropicMultimodalPartsIncludeDocumentOnly() {
        let document = ChatDocumentAttachment(filename: "spec.pdf", mimeType: "application/pdf", data: pdfHeader)
        let turn = ChatTurn(role: .user, content: "Summarize this", documents: [document])
        let parts = MultimodalRequestEncoder.anthropicParts(for: turn)
        XCTAssertEqual(parts?.count, 2)
        XCTAssertEqual(parts?[0].type, "document")
        XCTAssertEqual(parts?[0].source?.mediaType, "application/pdf")
        XCTAssertEqual(parts?[0].source?.data, document.data.base64EncodedString())
        XCTAssertEqual(parts?[1].type, "text")
        XCTAssertEqual(parts?[1].text, "Summarize this")
    }

    func testMultimodalPartsOrderDocumentsBeforeImagesBeforeText() {
        let document = ChatDocumentAttachment(filename: "spec.pdf", mimeType: "application/pdf", data: pdfHeader)
        let image = ChatImageAttachment(mimeType: "image/png", data: Data([1, 2, 3]))
        let turn = ChatTurn(role: .user, content: "Both", images: [image], documents: [document])

        let openAIParts = MultimodalRequestEncoder.openAIParts(for: turn)
        XCTAssertEqual(openAIParts?.map(\.type), ["file", "image_url", "text"])

        let anthropicParts = MultimodalRequestEncoder.anthropicParts(for: turn)
        XCTAssertEqual(anthropicParts?.map(\.type), ["document", "image", "text"])
    }

    func testMultimodalPartsForDocumentOnlyTurnAreNotNil() {
        let document = ChatDocumentAttachment(filename: "a.pdf", mimeType: "application/pdf", data: pdfHeader)
        let turn = ChatTurn(role: .user, content: "", documents: [document])
        XCTAssertNotNil(MultimodalRequestEncoder.openAIParts(for: turn))
        XCTAssertNotNil(MultimodalRequestEncoder.anthropicParts(for: turn))
    }
}

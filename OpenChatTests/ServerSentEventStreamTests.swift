import XCTest
@testable import OpenChat

final class ServerSentEventStreamTests: XCTestCase {
    func testExtractsDataPayload() {
        XCTAssertEqual(ServerSentEventStream.payload(fromSSELine: "data: {\"foo\":1}"), "{\"foo\":1}")
    }

    func testTrimsLeadingSpaceAfterColon() {
        XCTAssertEqual(ServerSentEventStream.payload(fromSSELine: "data:{\"foo\":1}"), "{\"foo\":1}")
    }

    func testIgnoresNonDataLines() {
        XCTAssertNil(ServerSentEventStream.payload(fromSSELine: "event: content_block_delta"))
        XCTAssertNil(ServerSentEventStream.payload(fromSSELine: ""))
        XCTAssertNil(ServerSentEventStream.payload(fromSSELine: ": comment"))
    }

    func testRecognizesDoneSentinel() {
        XCTAssertEqual(ServerSentEventStream.payload(fromSSELine: "data: [DONE]"), "[DONE]")
    }
}

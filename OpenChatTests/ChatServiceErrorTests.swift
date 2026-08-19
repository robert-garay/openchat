import XCTest
@testable import OpenChat

final class ChatServiceErrorTests: XCTestCase {
    func testTimedOutMessageExplainsCauseAndMitigations() {
        let message = ChatServiceError.timedOut.localizedDescription
        XCTAssertTrue(message.localizedCaseInsensitiveContains("timed out"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("long"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("try again"))
    }

    func testUserFacingMessageMapsURLTimeout() {
        let mapped = ChatServiceError.userFacingMessage(
            for: URLError(.timedOut)
        )
        XCTAssertEqual(mapped, ChatServiceError.timedOut.localizedDescription)
    }

    func testUserFacingMessageKeepsChatServiceErrors() {
        let mapped = ChatServiceError.userFacingMessage(
            for: ChatServiceError.cancelled
        )
        XCTAssertEqual(mapped, ChatServiceError.cancelled.localizedDescription)
    }

    func testConnectionDroppedMessageExplainsReconnection() {
        let message = ChatServiceError.connectionDropped.localizedDescription
        XCTAssertTrue(message.localizedCaseInsensitiveContains("connection"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("reconnect") || message.localizedCaseInsensitiveContains("resum"))
    }

    func testChatSessionUsesExtendedIdleTimeout() {
        let configuration = ChatService.urlSession.configuration
        XCTAssertGreaterThan(configuration.timeoutIntervalForRequest, 60)
        XCTAssertGreaterThanOrEqual(configuration.timeoutIntervalForResource, 3_600)
    }
}

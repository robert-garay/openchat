import XCTest
@testable import OpenChat

final class HTTPHeadersTests: XCTestCase {
    func testReservedHeaderNamesAreRejected() {
        for name in [
            "Authorization",
            "x-api-key",
            "Host",
            "Content-Type",
            "Proxy-Authorization",
            "cookie",
        ] {
            XCTAssertTrue(ProviderHTTPHeaders.isReservedHeaderName(name), name)
        }
        XCTAssertFalse(ProviderHTTPHeaders.isReservedHeaderName("x-opencode-session"))
    }

    func testSanitizeDropsReservedNamesAndControlCharacters() {
        let sanitized = ProviderHTTPHeaders.sanitizeCustomHeaders([
            "Authorization": "evil",
            "X-Custom": "ok\r\nInjected: true",
            "x-opencode-session": "session-1",
        ])
        XCTAssertNil(sanitized["Authorization"])
        XCTAssertEqual(sanitized["X-Custom"], "okInjected: true")
        XCTAssertEqual(sanitized["x-opencode-session"], "session-1")
    }

    func testInvalidHeaderNamesAreDropped() {
        let sanitized = ProviderHTTPHeaders.sanitizeCustomHeaders([
            "bad name": "value",
            "good-name": "value",
        ])
        XCTAssertNil(sanitized["bad name"])
        XCTAssertEqual(sanitized["good-name"], "value")
    }

    func testNonASCIIHeaderNamesAreDropped() {
        // RFC 9110 token characters are ASCII only. `x-café` and a Cyrillic
        // lookalike of `Authorization` must not pass validation.
        XCTAssertFalse(ProviderHTTPHeaders.isValidHeaderName("x-café"))
        XCTAssertFalse(ProviderHTTPHeaders.isValidHeaderName("Аuthorization"))
        XCTAssertTrue(ProviderHTTPHeaders.isValidHeaderName("x-custom_1"))

        let sanitized = ProviderHTTPHeaders.sanitizeCustomHeaders([
            "x-café": "value",
            "Аuthorization": "value",
        ])
        XCTAssertTrue(sanitized.isEmpty)
    }

    func testAuthHeaderCannotBeOverriddenByCustomHeaders() {
        var request = URLRequest(url: URL(string: "https://example.com/v1/chat/completions")!)
        request.applyCustomHeaders(["Authorization": "Bearer evil"])
        request.setValue("Bearer real-key", forHTTPHeaderField: "Authorization")
        request.applyOpenChatUserAgent()
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer real-key")
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.contains("OpenChat") == true)
    }

    func testOpenCodeSessionIsPerConversation() {
        let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let headers = ProviderHTTPHeaders.effectiveHeaders(
            stored: [:],
            template: ProviderTemplate.template(for: "opencode"),
            providerID: "opencode",
            conversationID: conversationID
        )
        XCTAssertEqual(headers["x-opencode-session"], "openchat-\(conversationID.uuidString)")
        XCTAssertEqual(headers["x-opencode-client"], "openchat")
    }

    func testCustomHeadersStoredInKeychain() {
        KeychainStore.service = "com.openchat.apikeys.tests.\(UUID().uuidString)"
        defer { KeychainStore.removeAll() }

        ProviderHTTPHeaders.saveToKeychain(["x-test": "secret"], providerID: "p1")
        XCTAssertEqual(ProviderHTTPHeaders.loadFromKeychain(providerID: "p1"), ["x-test": "secret"])
        ProviderHTTPHeaders.removeFromKeychain(providerID: "p1")
        XCTAssertTrue(ProviderHTTPHeaders.loadFromKeychain(providerID: "p1").isEmpty)
    }
}

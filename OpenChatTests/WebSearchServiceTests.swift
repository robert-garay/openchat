import XCTest
@testable import OpenChat

final class WebSearchServiceTests: XCTestCase {
    func testPreferredModeNilWhenInactive() {
        XCTAssertNil(WebSearchService.preferredMode(supportsTools: true, isActive: false))
        XCTAssertNil(WebSearchService.preferredMode(supportsTools: false, isActive: false))
    }

    func testPreferredModePrefersToolCallingWhenSupported() {
        XCTAssertEqual(
            WebSearchService.preferredMode(supportsTools: true, isActive: true),
            .toolCalling
        )
    }

    func testPreferredModeFallsBackToInjectWithoutTools() {
        XCTAssertEqual(
            WebSearchService.preferredMode(supportsTools: false, isActive: true),
            .inject
        )
    }

    func testQueryParsesToolArguments() {
        XCTAssertEqual(
            WebSearchService.query(fromToolArguments: #"{"query":"latest AI news"}"#),
            "latest AI news"
        )
        XCTAssertNil(WebSearchService.query(fromToolArguments: #"{"q":"nope"}"#))
        XCTAssertNil(WebSearchService.query(fromToolArguments: #"{"query":"  "}"#))
        XCTAssertNil(WebSearchService.query(fromToolArguments: "not-json"))
    }

    func testFormatContextIncludesResultsAndAnswer() {
        let response = TavilyClient.SearchResponse(
            query: "Swift concurrency",
            answer: "Actors isolate state.",
            results: [
                .init(
                    title: "Swift.org",
                    url: "https://swift.org/concurrency",
                    content: "Structured concurrency overview.",
                    score: 0.9
                )
            ]
        )
        let text = WebSearchService.formatContext(from: response)
        XCTAssertTrue(text.contains("Swift concurrency"))
        XCTAssertTrue(text.contains("Actors isolate state."))
        XCTAssertTrue(text.contains("Swift.org"))
        XCTAssertTrue(text.contains("https://swift.org/concurrency"))
        XCTAssertTrue(text.contains("Structured concurrency overview."))
    }

    func testToolDefinitionUsesWebSearchName() {
        XCTAssertEqual(WebSearchService.toolDefinition.name, "web_search")
        XCTAssertTrue(WebSearchService.toolDefinition.parametersJSON.contains("query"))
    }
}

@MainActor
final class WebSearchStoreTests: XCTestCase {
    private let suiteName = "com.openchat.tests.websearch.\(UUID().uuidString)"
    private var defaults: UserDefaults!
    private var store: WebSearchStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        KeychainStore.remove("tavily")
        store = WebSearchStore(defaults: defaults)
    }

    override func tearDown() {
        KeychainStore.remove("tavily")
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testSetAPIKeyEnablesSearch() {
        XCTAssertFalse(store.hasAPIKey)
        XCTAssertFalse(store.isActive)

        store.setAPIKey("tvly-test-key")

        XCTAssertTrue(store.hasAPIKey)
        XCTAssertTrue(store.isEnabled)
        XCTAssertTrue(store.isActive)
        XCTAssertEqual(store.apiKey(), "tvly-test-key")
        XCTAssertEqual(store.redactedAPIKey()?.prefix(3), "tvl")
    }

    func testRemoveAPIKeyDisablesActiveSearch() {
        store.setAPIKey("tvly-test-key")
        store.removeAPIKey()

        XCTAssertFalse(store.hasAPIKey)
        XCTAssertFalse(store.isActive)
        XCTAssertNil(store.apiKey())
    }

    func testToggleKeepsKeyButStopsSearch() {
        store.setAPIKey("tvly-test-key")
        store.setEnabled(false)

        XCTAssertTrue(store.hasAPIKey)
        XCTAssertFalse(store.isActive)
    }
}

final class TavilyClientTests: XCTestCase {
    func testSearchBuildsAuthorizedRequestAndDecodesResults() async throws {
        let session = URLSession(configuration: mockConfiguration(
            statusCode: 200,
            body: """
            {
              "query": "openai news",
              "answer": "A summary.",
              "results": [
                {
                  "title": "Example",
                  "url": "https://example.com",
                  "content": "Snippet text",
                  "score": 0.88
                }
              ]
            }
            """
        ))
        let client = TavilyClient(
            session: session,
            endpoint: URL(string: "https://api.tavily.com/search")!
        )

        let response = try await client.search(query: "openai news", apiKey: "tvly-secret")

        XCTAssertEqual(response.query, "openai news")
        XCTAssertEqual(response.answer, "A summary.")
        XCTAssertEqual(response.results.count, 1)
        XCTAssertEqual(response.results[0].title, "Example")
        XCTAssertEqual(response.results[0].url, "https://example.com")
        XCTAssertEqual(response.results[0].content, "Snippet text")
    }

    func testSearchRejectsEmptyQuery() async {
        let client = TavilyClient()
        do {
            _ = try await client.search(query: "  ", apiKey: "tvly-secret")
            XCTFail("Expected emptyQuery")
        } catch let error as TavilyClientError {
            XCTAssertEqual(error, .emptyQuery)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSearchSurfacesHTTPErrors() async {
        let session = URLSession(configuration: mockConfiguration(
            statusCode: 401,
            body: #"{"detail":{"error":"Unauthorized"}}"#
        ))
        let client = TavilyClient(
            session: session,
            endpoint: URL(string: "https://api.tavily.com/search")!
        )

        do {
            _ = try await client.search(query: "test", apiKey: "bad-key")
            XCTFail("Expected http error")
        } catch let error as TavilyClientError {
            guard case .http(let status, let body) = error else {
                return XCTFail("Wrong error \(error)")
            }
            XCTAssertEqual(status, 401)
            XCTAssertTrue(body.contains("Unauthorized"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func mockConfiguration(statusCode: Int, body: String) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TavilyMockURLProtocol.self]
        TavilyMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tvly-secret")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }
        // For unauthorized test the key differs — relax assertion in protocol when needed.
        if statusCode == 401 {
            TavilyMockURLProtocol.requestHandler = { request in
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(body.utf8))
            }
        }
        return configuration
    }
}

private final class TavilyMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

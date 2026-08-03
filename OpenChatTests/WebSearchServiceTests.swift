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
        let response = WebSearchResponse(
            query: "Swift concurrency",
            providerName: "Tavily",
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
        XCTAssertTrue(text.contains("via Tavily"))
        XCTAssertTrue(text.contains("Actors isolate state."))
        XCTAssertTrue(text.contains("Swift.org"))
        XCTAssertTrue(text.contains("https://swift.org/concurrency"))
        XCTAssertTrue(text.contains("Structured concurrency overview."))
    }

    func testToolDefinitionUsesWebSearchName() {
        let tool = WebSearchService.toolDefinition(providerName: "Exa")
        XCTAssertEqual(tool.name, "web_search")
        XCTAssertTrue(tool.description.contains("Exa"))
        XCTAssertTrue(tool.parametersJSON.contains("query"))
    }

    func testSearchOnlyProvidersAreListed() {
        let ids = WebSearchProviderKind.allCases.map(\.rawValue)
        XCTAssertEqual(ids, ["tavily", "exa", "brave", "serper", "serpAPI"])
    }

    func testEachProviderHasLogoAssetMapping() {
        for kind in WebSearchProviderKind.allCases {
            XCTAssertFalse(kind.logoAssetName.isEmpty, "\(kind.displayName) missing logo asset")
            XCTAssertTrue(kind.logoAssetName.hasPrefix("SearchLogo"))
        }
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
        for kind in WebSearchProviderKind.allCases {
            KeychainStore.remove(kind.keychainAccount)
            if let legacy = kind.legacyKeychainAccount {
                KeychainStore.remove(legacy)
            }
        }
        store = WebSearchStore(defaults: defaults)
    }

    override func tearDown() {
        for kind in WebSearchProviderKind.allCases {
            KeychainStore.remove(kind.keychainAccount)
            if let legacy = kind.legacyKeychainAccount {
                KeychainStore.remove(legacy)
            }
        }
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testSetAPIKeyEnablesSearchAndBecomesActive() {
        XCTAssertFalse(store.hasAnyAPIKey)
        XCTAssertFalse(store.isActive)

        store.setAPIKey("tvly-test-key", for: .tavily)

        XCTAssertTrue(store.hasAPIKey(for: .tavily))
        XCTAssertTrue(store.isEnabled)
        XCTAssertEqual(store.activeProvider, .tavily)
        XCTAssertTrue(store.isActive)
        XCTAssertEqual(store.activeAPIKey(), "tvly-test-key")
    }

    func testMultipleKeysUseSelectedActiveProvider() {
        store.setAPIKey("tvly-key", for: .tavily)
        store.setAPIKey("exa-key", for: .exa)
        store.setActiveProvider(.exa)

        XCTAssertEqual(store.configuredProviders.count, 2)
        XCTAssertEqual(store.activeProvider, .exa)
        XCTAssertEqual(store.activeAPIKey(), "exa-key")
    }

    func testRemoveActiveFallsBackToAnotherConfiguredProvider() {
        store.setAPIKey("tvly-key", for: .tavily)
        store.setAPIKey("brave-key", for: .brave)
        store.setActiveProvider(.brave)
        store.removeAPIKey(for: .brave)

        XCTAssertFalse(store.hasAPIKey(for: .brave))
        XCTAssertEqual(store.activeProvider, .tavily)
        XCTAssertTrue(store.isActive)
    }

    func testToggleKeepsKeyButStopsSearch() {
        store.setAPIKey("tvly-test-key", for: .tavily)
        store.setEnabled(false)

        XCTAssertTrue(store.hasAnyAPIKey)
        XCTAssertFalse(store.isActive)
    }

    func testMigratesLegacyTavilyKeychainAccount() {
        KeychainStore.set("legacy-tavily", forKey: "tavily")
        let migrated = WebSearchStore(defaults: defaults)
        XCTAssertEqual(migrated.apiKey(for: .tavily), "legacy-tavily")
        XCTAssertNil(KeychainStore.get("tavily"))
        XCTAssertEqual(KeychainStore.get("websearch.tavily"), "legacy-tavily")
    }
}

final class WebSearchClientTests: XCTestCase {
    func testTavilySearchBuildsAuthorizedRequestAndDecodesResults() async throws {
        let session = URLSession(configuration: mockConfiguration { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tvly-secret")
            return (
                200,
                """
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
            )
        })
        let client = TavilyClient(session: session)
        let response = try await client.search(query: "openai news", apiKey: "tvly-secret")
        XCTAssertEqual(response.providerName, "Tavily")
        XCTAssertEqual(response.results.first?.title, "Example")
    }

    func testBraveSearchDecodesWebResults() async throws {
        let session = URLSession(configuration: mockConfiguration { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Subscription-Token"), "brave-key")
            return (
                200,
                """
                {
                  "query": { "original": "swift" },
                  "web": {
                    "results": [
                      { "title": "Swift.org", "url": "https://swift.org", "description": "Apple's Swift" }
                    ]
                  }
                }
                """
            )
        })
        let client = BraveSearchClient(session: session)
        let response = try await client.search(query: "swift", apiKey: "brave-key")
        XCTAssertEqual(response.providerName, "Brave Search")
        XCTAssertEqual(response.results.first?.url, "https://swift.org")
    }

    func testSerperAndSerpAPIDecodeOrganicResults() async throws {
        let serperSession = URLSession(configuration: mockConfiguration { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-KEY"), "serper-key")
            return (
                200,
                """
                {
                  "organic": [
                    { "title": "A", "link": "https://a.example", "snippet": "one" }
                  ]
                }
                """
            )
        })
        let serper = try await SerperClient(session: serperSession).search(query: "q", apiKey: "serper-key")
        XCTAssertEqual(serper.results.first?.title, "A")

        let serpAPISession = URLSession(configuration: mockConfiguration { _ in
            (
                200,
                """
                {
                  "organic_results": [
                    { "title": "B", "link": "https://b.example", "snippet": "two" }
                  ]
                }
                """
            )
        })
        let serpAPI = try await SerpAPIClient(session: serpAPISession).search(query: "q", apiKey: "serp-key")
        XCTAssertEqual(serpAPI.providerName, "SerpAPI")
        XCTAssertEqual(serpAPI.results.first?.title, "B")
    }

    func testSearchRejectsEmptyQuery() async {
        do {
            _ = try await TavilyClient().search(query: "  ", apiKey: "k")
            XCTFail("Expected emptyQuery")
        } catch let error as WebSearchClientError {
            XCTAssertEqual(error, .emptyQuery)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func mockConfiguration(
        _ handler: @escaping (URLRequest) -> (Int, String)
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WebSearchMockURLProtocol.self]
        WebSearchMockURLProtocol.requestHandler = { request in
            let (status, body) = handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }
        return configuration
    }
}

private final class WebSearchMockURLProtocol: URLProtocol, @unchecked Sendable {
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

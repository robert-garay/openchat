import Foundation

/// Brave Search API (`GET https://api.search.brave.com/res/v1/web/search`).
struct BraveSearchClient: WebSearchClient {
    var session: URLSession = .shared
    var endpoint: URL = URL(string: "https://api.search.brave.com/res/v1/web/search")!

    func search(query: String, apiKey: String, maxResults: Int = 5) async throws -> WebSearchResponse {
        let trimmedQuery = try Self.requireQuery(query)
        try Self.requireKey(apiKey)

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "count", value: String(maxResults)),
        ]
        guard let url = components.url else { throw WebSearchClientError.emptyQuery }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")

        let (data, response) = try await session.data(for: request)
        try Self.throwIfNeeded(response: response, data: data)

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        return WebSearchResponse(
            query: decoded.query?.original ?? trimmedQuery,
            providerName: WebSearchProviderKind.brave.displayName,
            answer: nil,
            results: (decoded.web?.results ?? []).prefix(maxResults).map {
                WebSearchHit(
                    title: $0.title ?? "",
                    url: $0.url ?? "",
                    content: $0.description ?? "",
                    score: nil
                )
            }
        )
    }

    private struct APIResponse: Decodable {
        var query: Query?
        var web: Web?

        struct Query: Decodable {
            var original: String?
        }

        struct Web: Decodable {
            var results: [APIResult]?
        }

        struct APIResult: Decodable {
            var title: String?
            var url: String?
            var description: String?
        }
    }
}

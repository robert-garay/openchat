import Foundation

/// Minimal Tavily Search client (`POST https://api.tavily.com/search`).
struct TavilyClient: WebSearchClient {
    var session: URLSession = .shared
    var endpoint: URL = URL(string: "https://api.tavily.com/search")!

    func search(query: String, apiKey: String, maxResults: Int = 5) async throws -> WebSearchResponse {
        let trimmedQuery = try Self.requireQuery(query)
        try Self.requireKey(apiKey)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(query: trimmedQuery, maxResults: maxResults, includeAnswer: true)
        )

        let (data, response) = try await session.backgroundCompatibleData(for: request)
        try Self.throwIfNeeded(response: response, data: data)

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        return WebSearchResponse(
            query: decoded.query ?? trimmedQuery,
            providerName: WebSearchProviderKind.tavily.displayName,
            answer: decoded.answer,
            results: (decoded.results ?? []).map {
                WebSearchHit(
                    title: $0.title ?? "",
                    url: $0.url ?? "",
                    content: $0.content ?? "",
                    score: $0.score
                )
            }
        )
    }

    private struct RequestBody: Encodable {
        var query: String
        var maxResults: Int
        var includeAnswer: Bool
        var searchDepth = "basic"

        enum CodingKeys: String, CodingKey {
            case query
            case maxResults = "max_results"
            case includeAnswer = "include_answer"
            case searchDepth = "search_depth"
        }
    }

    private struct APIResponse: Decodable {
        var query: String?
        var answer: String?
        var results: [APIResult]?
    }

    private struct APIResult: Decodable {
        var title: String?
        var url: String?
        var content: String?
        var score: Double?
    }
}

extension WebSearchClient {
    static func requireQuery(_ query: String) throws -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WebSearchClientError.emptyQuery }
        return trimmed
    }

    static func requireKey(_ apiKey: String) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WebSearchClientError.missingAPIKey
        }
    }

    static func throwIfNeeded(response: URLResponse, data: Data) throws {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WebSearchClientError.http(status: http.statusCode, body: body)
        }
    }
}

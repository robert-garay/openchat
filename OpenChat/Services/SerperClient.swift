import Foundation

/// Serper Google Search (`POST https://google.serper.dev/search`).
struct SerperClient: WebSearchClient {
    var session: URLSession = .shared
    var endpoint: URL = URL(string: "https://google.serper.dev/search")!

    func search(query: String, apiKey: String, maxResults: Int = 5) async throws -> WebSearchResponse {
        let trimmedQuery = try Self.requireQuery(query)
        try Self.requireKey(apiKey)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        request.httpBody = try JSONEncoder().encode(RequestBody(q: trimmedQuery, num: maxResults))

        let (data, response) = try await session.backgroundCompatibleData(for: request)
        try Self.throwIfNeeded(response: response, data: data)

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        return WebSearchResponse(
            query: trimmedQuery,
            providerName: WebSearchProviderKind.serper.displayName,
            answer: decoded.answerBox?.answer ?? decoded.answerBox?.snippet,
            results: (decoded.organic ?? []).prefix(maxResults).map {
                WebSearchHit(
                    title: $0.title ?? "",
                    url: $0.link ?? "",
                    content: $0.snippet ?? "",
                    score: nil
                )
            }
        )
    }

    private struct RequestBody: Encodable {
        var q: String
        var num: Int
    }

    private struct APIResponse: Decodable {
        var organic: [Organic]?
        var answerBox: AnswerBox?

        struct Organic: Decodable {
            var title: String?
            var link: String?
            var snippet: String?
        }

        struct AnswerBox: Decodable {
            var answer: String?
            var snippet: String?
        }
    }
}

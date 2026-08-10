import Foundation

/// SerpAPI Google Search (`GET https://serpapi.com/search.json`).
struct SerpAPIClient: WebSearchClient {
    var session: URLSession = .shared
    var endpoint: URL = URL(string: "https://serpapi.com/search.json")!

    func search(query: String, apiKey: String, maxResults: Int = 5) async throws -> WebSearchResponse {
        let trimmedQuery = try Self.requireQuery(query)
        try Self.requireKey(apiKey)

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "engine", value: "google"),
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "num", value: String(maxResults)),
        ]
        guard let url = components.url else { throw WebSearchClientError.emptyQuery }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.backgroundCompatibleData(for: request)
        try Self.throwIfNeeded(response: response, data: data)

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        return WebSearchResponse(
            query: trimmedQuery,
            providerName: WebSearchProviderKind.serpAPI.displayName,
            answer: decoded.answerBox?.answer ?? decoded.answerBox?.snippet,
            results: (decoded.organicResults ?? []).prefix(maxResults).map {
                WebSearchHit(
                    title: $0.title ?? "",
                    url: $0.link ?? "",
                    content: $0.snippet ?? "",
                    score: nil
                )
            }
        )
    }

    private struct APIResponse: Decodable {
        var organicResults: [Organic]?
        var answerBox: AnswerBox?

        enum CodingKeys: String, CodingKey {
            case organicResults = "organic_results"
            case answerBox = "answer_box"
        }

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

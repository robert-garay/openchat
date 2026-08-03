import Foundation

/// Exa neural search (`POST https://api.exa.ai/search`).
struct ExaClient: WebSearchClient {
    var session: URLSession = .shared
    var endpoint: URL = URL(string: "https://api.exa.ai/search")!

    func search(query: String, apiKey: String, maxResults: Int = 5) async throws -> WebSearchResponse {
        let trimmedQuery = try Self.requireQuery(query)
        try Self.requireKey(apiKey)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                query: trimmedQuery,
                numResults: maxResults,
                contents: .init(text: .init(maxCharacters: 1000))
            )
        )

        let (data, response) = try await session.data(for: request)
        try Self.throwIfNeeded(response: response, data: data)

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        return WebSearchResponse(
            query: trimmedQuery,
            providerName: WebSearchProviderKind.exa.displayName,
            answer: nil,
            results: (decoded.results ?? []).map {
                WebSearchHit(
                    title: $0.title ?? "",
                    url: $0.url ?? "",
                    content: $0.text ?? $0.summary ?? "",
                    score: $0.score
                )
            }
        )
    }

    private struct RequestBody: Encodable {
        var query: String
        var numResults: Int
        var contents: Contents

        struct Contents: Encodable {
            var text: TextOptions
        }

        struct TextOptions: Encodable {
            var maxCharacters: Int
        }
    }

    private struct APIResponse: Decodable {
        var results: [APIResult]?
    }

    private struct APIResult: Decodable {
        var title: String?
        var url: String?
        var text: String?
        var summary: String?
        var score: Double?
    }
}

import Foundation

/// Minimal Tavily Search client. Calls `POST https://api.tavily.com/search`
/// with the user's BYOK key and returns LLM-friendly result snippets.
struct TavilyClient: Sendable {
    var session: URLSession = .shared
    var endpoint: URL = URL(string: "https://api.tavily.com/search")!

    struct SearchResult: Equatable, Sendable {
        var title: String
        var url: String
        var content: String
        var score: Double?
    }

    struct SearchResponse: Equatable, Sendable {
        var query: String
        var answer: String?
        var results: [SearchResult]
    }

    func search(
        query: String,
        apiKey: String,
        maxResults: Int = 5
    ) async throws -> SearchResponse {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw TavilyClientError.emptyQuery
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TavilyClientError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(query: trimmedQuery, maxResults: maxResults, includeAnswer: true)
        )

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TavilyClientError.http(status: http.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        return SearchResponse(
            query: decoded.query ?? trimmedQuery,
            answer: decoded.answer,
            results: (decoded.results ?? []).map {
                SearchResult(
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

enum TavilyClientError: LocalizedError, Equatable {
    case emptyQuery
    case missingAPIKey
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Search query is empty."
        case .missingAPIKey:
            return "No Tavily API key configured."
        case .http(let status, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Tavily request failed with status \(status)."
            }
            return "Tavily request failed (\(status)): \(trimmed)"
        }
    }
}

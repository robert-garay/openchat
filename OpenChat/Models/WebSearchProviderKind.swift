import Foundation

/// Search-only BYOK providers (no crawl/extract).
enum WebSearchProviderKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case tavily
    case exa
    case brave
    case serper
    case serpAPI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tavily: "Tavily"
        case .exa: "Exa"
        case .brave: "Brave Search"
        case .serper: "Serper"
        case .serpAPI: "SerpAPI"
        }
    }

    var subtitle: String {
        switch self {
        case .tavily: "Agent-oriented web search"
        case .exa: "Neural / semantic web search"
        case .brave: "Independent Brave web index"
        case .serper: "Google results via Serper"
        case .serpAPI: "Google results via SerpAPI"
        }
    }

    var symbolName: String {
        switch self {
        case .tavily: "globe"
        case .exa: "sparkles"
        case .brave: "shield.lefthalf.filled"
        case .serper: "magnifyingglass"
        case .serpAPI: "list.bullet.rectangle"
        }
    }

    /// Asset catalog logo used in Settings / pickers.
    var logoAssetName: String {
        switch self {
        case .tavily: "SearchLogoTavily"
        case .exa: "SearchLogoExa"
        case .brave: "SearchLogoBrave"
        case .serper: "SearchLogoSerper"
        case .serpAPI: "SearchLogoSerpAPI"
        }
    }

    /// Soft chip tint behind the logo (matches ProviderLogoView usage).
    var tintHex: String {
        switch self {
        case .tavily: "0F172A"
        case .exa: "2E47E6"
        case .brave: "FB542B"
        case .serper: "5BA4D9"
        case .serpAPI: "5B4BDB"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .tavily: "tvly-…"
        case .exa: "exa-…"
        case .brave: "BSA…"
        case .serper: "Serper API key"
        case .serpAPI: "SerpAPI key"
        }
    }

    var keyHelpURL: URL? {
        switch self {
        case .tavily: URL(string: "https://app.tavily.com/home")
        case .exa: URL(string: "https://dashboard.exa.ai/api-keys")
        case .brave: URL(string: "https://api-dashboard.search.brave.com/")
        case .serper: URL(string: "https://serper.dev/api-key")
        case .serpAPI: URL(string: "https://serpapi.com/manage-api-key")
        }
    }

    /// Keychain account. Legacy Tavily keys used bare `"tavily"`.
    var keychainAccount: String { "websearch.\(rawValue)" }

    var legacyKeychainAccount: String? {
        self == .tavily ? "tavily" : nil
    }
}

struct WebSearchHit: Equatable, Sendable {
    var title: String
    var url: String
    var content: String
    var score: Double?
}

struct WebSearchResponse: Equatable, Sendable {
    var query: String
    var providerName: String
    var answer: String?
    var results: [WebSearchHit]
}

enum WebSearchClientError: LocalizedError, Equatable {
    case emptyQuery
    case missingAPIKey
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Search query is empty."
        case .missingAPIKey:
            return "No search API key configured."
        case .http(let status, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Search request failed with status \(status)."
            }
            return "Search request failed (\(status)): \(trimmed)"
        }
    }
}

protocol WebSearchClient: Sendable {
    func search(query: String, apiKey: String, maxResults: Int) async throws -> WebSearchResponse
}

enum WebSearchClientFactory {
    static func client(for kind: WebSearchProviderKind) -> any WebSearchClient {
        switch kind {
        case .tavily: TavilyClient()
        case .exa: ExaClient()
        case .brave: BraveSearchClient()
        case .serper: SerperClient()
        case .serpAPI: SerpAPIClient()
        }
    }
}

import Foundation

/// Chooses how to attach web search to a chat request and formats results.
enum WebSearchMode: String, Equatable, Sendable {
    /// Model supports tools — expose `web_search` and let it decide when to call.
    case toolCalling
    /// Model has no tools — search the latest user message and inject results.
    case inject
}

enum WebSearchService {
    static let toolName = "web_search"
    static let maxToolRounds = 3

    static func preferredMode(supportsTools: Bool, isActive: Bool) -> WebSearchMode? {
        guard isActive else { return nil }
        return supportsTools ? .toolCalling : .inject
    }

    static func toolDefinition(providerName: String) -> ChatToolDefinition {
        ChatToolDefinition(
            name: toolName,
            description: """
            Search the live web via \(providerName) for up-to-date facts, news, and sources. \
            Use when the user asks about current events, recent data, or anything that may be outdated in training data.
            """,
            parametersJSON: """
            {
              "type": "object",
              "properties": {
                "query": {
                  "type": "string",
                  "description": "The search query to run."
                }
              },
              "required": ["query"]
            }
            """
        )
    }

    /// Backward-compatible default tool schema.
    static var toolDefinition: ChatToolDefinition {
        toolDefinition(providerName: "the configured search provider")
    }

    static func query(fromToolArguments argumentsJSON: String) -> String? {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = object["query"] as? String
        else {
            return nil
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Formats search results for injection into a system/tool turn.
    static func formatContext(from response: WebSearchResponse) -> String {
        var lines: [String] = [
            "Web search results for \"\(response.query)\" (via \(response.providerName)). Cite sources with URLs when relevant. Do not invent sources beyond this list."
        ]

        if let answer = response.answer?.trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty {
            lines.append("")
            lines.append("Summary: \(answer)")
        }

        if response.results.isEmpty {
            lines.append("")
            lines.append("No results returned.")
            return lines.joined(separator: "\n")
        }

        lines.append("")
        for (index, result) in response.results.enumerated() {
            let title = result.title.isEmpty ? "Result \(index + 1)" : result.title
            lines.append("\(index + 1). \(title)")
            if !result.url.isEmpty {
                lines.append("   URL: \(result.url)")
            }
            let snippet = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !snippet.isEmpty {
                lines.append("   \(snippet)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Runs a search and returns a context block suitable for inject mode.
    static func makeInjectedContext(
        query: String,
        apiKey: String,
        client: any WebSearchClient
    ) async throws -> String {
        let response = try await client.search(query: query, apiKey: apiKey, maxResults: 5)
        return formatContext(from: response)
    }

    /// Executes a `web_search` tool call and returns the tool result string.
    static func executeToolCall(
        _ call: ChatToolCall,
        apiKey: String,
        client: any WebSearchClient
    ) async throws -> String {
        guard call.name == toolName else {
            return "Unknown tool: \(call.name)"
        }
        guard let query = query(fromToolArguments: call.argumentsJSON) else {
            return "Invalid web_search arguments. Expected JSON with a \"query\" string."
        }
        let response = try await client.search(query: query, apiKey: apiKey, maxResults: 5)
        return formatContext(from: response)
    }
}

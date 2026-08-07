import Foundation

/// Lightweight token-based fuzzy matcher for local model/skill search.
///
/// Splits the query on whitespace and requires every token to appear somewhere
/// in the searchable text. Tokens also match when separator characters are
/// stripped, so queries like `"gpt nano"` or `"5nano"` match `"gpt-5-nano"`.
enum FuzzyMatcher {
    /// Characters treated as word boundaries when tokenizing.
    private static var separators: CharacterSet {
        .whitespacesAndNewlines.union(.init(charactersIn: "-_/."))
    }

    /// Returns true if every whitespace-separated token in `query` is found in
    /// at least one of the provided `fields`.
    ///
    /// Matching rules for each query token:
    /// 1. Substring of the original joined text (e.g. `"5-nano"` matches).
    /// 2. Substring of the separator-stripped text (e.g. `"5nano"` matches
    ///    `"gpt-5-nano"`).
    static func matches(query: String, fields: [String]) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let queryTokens = trimmed
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard !queryTokens.isEmpty else { return true }

        let joined = fields.joined(separator: " ")
        let normalized = joined.lowercased()
        let stripped = normalized.components(separatedBy: separators).joined()

        return queryTokens.allSatisfy { token in
            normalized.contains(token) || stripped.contains(token)
        }
    }
}

import Foundation
import os

/// Creates ChatGPT-style short titles from the first user message.
enum ConversationTitleGenerator {
    private static let logger = Logger(subsystem: "com.openchat.app", category: "ConversationTitleGenerator")
    static let systemPrompt = """
    Generate a concise chat title of 2 to 6 words that captures the user's message. \
    Reply with only the title. Do not use quotation marks, trailing punctuation, \
    prefixes like "Title:", or explanations.
    """

    /// Immediate sidebar title while a polished LLM title is generating.
    static func fallbackTitle(for userText: String, hasImages: Bool) -> String {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return hasImages ? "Image" : "New Chat"
        }

        let singleLine = trimmed
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if singleLine.count <= 40 {
            return singleLine
        }

        let prefix = String(singleLine.prefix(40))
        if let lastSpace = prefix.lastIndex(of: " "), lastSpace > prefix.startIndex {
            return String(prefix[..<lastSpace])
        }
        return prefix
    }

    /// Cleans a model reply into a usable chat title, or `nil` if unusable.
    static func sanitize(_ raw: String) -> String? {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let newline = title.firstIndex(of: "\n") {
            title = String(title[..<newline])
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Markdown syntax characters are never meaningful literal content in a short
        // generated title, so they're removed outright rather than merely trimmed —
        // this also handles inline cases like "`inline code` title".
        for markdownCharacter in ["*", "_", "`"] {
            title = title.replacingOccurrences(of: markdownCharacter, with: "")
        }
        title = String(title.drop(while: { $0 == "#" }))
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let quoteScalars = CharacterSet(charactersIn: "\"'`“”‘’«»")
        let punctuationScalars = CharacterSet(charactersIn: ".!?。…")
        var previous = ""
        while previous != title {
            previous = title
            while let scalar = title.unicodeScalars.first, quoteScalars.contains(scalar) {
                title.removeFirst()
            }
            while let scalar = title.unicodeScalars.last, quoteScalars.contains(scalar) {
                title.removeLast()
            }
            title = title.trimmingCharacters(in: punctuationScalars)
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let lower = title.lowercased()
        for prefix in ["title:", "chat title:", "conversation title:"] {
            if lower.hasPrefix(prefix) {
                title = String(title.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        guard !title.isEmpty else { return nil }

        if title.count > 60 {
            let clipped = String(title.prefix(60))
            if let lastSpace = clipped.lastIndex(of: " "), lastSpace > clipped.startIndex {
                title = String(clipped[..<lastSpace])
            } else {
                title = clipped
            }
        }

        let final = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return final.isEmpty ? nil : final
    }

    /// Asks the chat model for a short title. Returns `nil` on failure.
    static func generate(
        from userText: String,
        client: ChatCompletionClient,
        model: String,
        baseURL: String,
        apiKey: String?
    ) async -> String? {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let turns = [
            ChatTurn(role: .system, content: systemPrompt),
            ChatTurn(role: .user, content: trimmed),
        ]

        var collected = ""
        do {
            for try await event in client.streamReply(
                turns: turns,
                model: model,
                baseURL: baseURL,
                apiKey: apiKey
            ) {
                if case .text(let delta) = event {
                    collected += delta
                }
            }
        } catch {
            logger.error("title generation stream failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        let sanitized = sanitize(collected)
        if sanitized == nil {
            logger.error("title generation produced unusable output, raw=\(collected, privacy: .public)")
        }
        return sanitized
    }
}

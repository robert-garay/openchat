import Foundation

/// Assembles the combined system prompt from tools, global rules, middle sections, and per-chat rules.
enum ChatSystemPromptBuilder {
    static func assemble(
        globalRules: String,
        chatRules: String,
        middleSections: [String],
        webSearchToolPrompt: String?
    ) -> String? {
        var systemParts: [String] = []

        if let webSearchToolPrompt, !webSearchToolPrompt.isEmpty {
            systemParts.append(webSearchToolPrompt)
        }

        let trimmedGlobal = globalRules.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGlobal.isEmpty {
            systemParts.append(trimmedGlobal)
        }

        for section in middleSections where !section.isEmpty {
            systemParts.append(section)
        }

        let trimmedChat = chatRules.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedChat.isEmpty {
            systemParts.append("Chat rules:\n\(trimmedChat)")
        }

        guard !systemParts.isEmpty else { return nil }
        return systemParts.joined(separator: "\n\n")
    }
}

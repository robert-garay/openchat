import Foundation

enum CompactConversationSettings {
    static let enabledKey = "com.openchat.compact.enabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledKey)
    }
}

/// Lightweight message snapshot for compaction planning and tests.
struct CompactionMessageSnapshot: Sendable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let imageCount: Int
    let createdAt: Date
}

enum ConversationCompactionService {
    /// Number of recent messages kept verbatim when compacting.
    static let recentKeepCount = 8

    /// Minimum total messages required before compact is allowed.
    static let minimumMessageCount = recentKeepCount + 2

    struct CompactionPlan: Equatable {
        let messagesToSummarize: [CompactionMessageSnapshot]
        let recentMessages: [CompactionMessageSnapshot]
        /// Last message ID included in the new summary region.
        let watermarkMessageID: UUID
    }

    static func snapshot(from message: ChatMessage) -> CompactionMessageSnapshot {
        CompactionMessageSnapshot(
            id: message.id,
            role: message.role,
            content: message.content,
            imageCount: message.imageAttachments.count,
            createdAt: message.createdAt
        )
    }

    static func snapshots(from messages: [ChatMessage]) -> [CompactionMessageSnapshot] {
        messages.map(snapshot(from:))
    }

    static func eligibleMessages(from snapshots: [CompactionMessageSnapshot]) -> [CompactionMessageSnapshot] {
        snapshots.filter { !$0.content.isEmpty || $0.imageCount > 0 }
    }

    static func canCompact(messageCount: Int) -> Bool {
        messageCount >= minimumMessageCount
    }

    /// Returns a compaction plan, or `nil` when the thread is too short or nothing new to summarize.
    static func planCompaction(
        sortedMessages: [CompactionMessageSnapshot],
        compactedThroughMessageID: UUID?
    ) -> CompactionPlan? {
        let eligible = eligibleMessages(from: sortedMessages)
        guard canCompact(messageCount: eligible.count) else { return nil }

        let recentMessages = Array(eligible.suffix(recentKeepCount))
        let summarizeEndIndex = eligible.count - recentKeepCount

        var startIndex = 0
        if let watermarkID = compactedThroughMessageID,
           let watermarkIndex = eligible.firstIndex(where: { $0.id == watermarkID }) {
            startIndex = watermarkIndex + 1
        }

        guard startIndex < summarizeEndIndex else { return nil }

        let messagesToSummarize = Array(eligible[startIndex..<summarizeEndIndex])
        guard let watermarkMessageID = messagesToSummarize.last?.id else { return nil }

        return CompactionPlan(
            messagesToSummarize: messagesToSummarize,
            recentMessages: recentMessages,
            watermarkMessageID: watermarkMessageID
        )
    }

    static func lineForSummarization(_ message: CompactionMessageSnapshot) -> String {
        let roleLabel: String
        switch message.role {
        case .user: roleLabel = "User"
        case .assistant: roleLabel = "Assistant"
        case .system: roleLabel = "System"
        case .tool: roleLabel = "Tool"
        }

        var line = "\(roleLabel): \(message.content)"
        if message.imageCount > 0 {
            let noun = message.imageCount == 1 ? "image" : "images"
            line += " [shared \(message.imageCount) \(noun)]"
        }
        return line
    }

    static func transcriptForSummarization(
        existingSummary: String?,
        messages: [CompactionMessageSnapshot]
    ) -> String {
        var parts: [String] = []
        if let existingSummary, !existingSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Previous summary:\n\(existingSummary)")
        }
        if !messages.isEmpty {
            let body = messages.map(lineForSummarization).joined(separator: "\n\n")
            parts.append("Conversation excerpt:\n\(body)")
        }
        return parts.joined(separator: "\n\n")
    }

    static func summarizationSystemPrompt() -> String {
        """
        You summarize prior chat messages for long-running conversations. Produce a structured, concise summary that preserves key facts, decisions, preferences, names, and open questions. Use short sections or bullet points. When images were shared, note that fact without inventing visual details.
        """
    }

    static func summarizationUserPrompt(transcript: String) -> String {
        """
        Summarize the following conversation material into a single structured summary suitable as context for future messages.

        \(transcript)
        """
    }

    /// Builds chat turns for API requests, injecting compact summary before post-watermark messages.
    static func apiHistoryTurns(
        sortedMessages: [ChatMessage],
        compactedSummary: String?,
        compactedThroughMessageID: UUID?,
        excludingMessageID: UUID? = nil
    ) -> [ChatTurn] {
        let eligible = sortedMessages.filter {
            $0.id != excludingMessageID
                && (!$0.content.isEmpty || !$0.imageAttachments.isEmpty)
                && !($0.role == .assistant && $0.isStreaming)
        }

        let summary = compactedSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasSummary = !summary.isEmpty

        let postWatermarkMessages: [ChatMessage]
        if hasSummary, let watermarkID = compactedThroughMessageID,
           let watermarkIndex = eligible.firstIndex(where: { $0.id == watermarkID }) {
            postWatermarkMessages = Array(eligible[(watermarkIndex + 1)...])
        } else if hasSummary {
            postWatermarkMessages = []
        } else {
            postWatermarkMessages = eligible
        }

        var turns: [ChatTurn] = []
        if hasSummary {
            turns.append(
                ChatTurn(
                    role: .user,
                    content: "[Compacted conversation context]\n\n\(summary)"
                )
            )
        }

        turns.append(contentsOf: postWatermarkMessages.map { message in
            ChatTurn(
                role: message.role,
                content: message.content,
                images: message.imageAttachments
            )
        })

        return turns
    }
}

import Foundation

/// Decides which images in a conversation get sent at full fidelity on a given turn.
///
/// The chat/completion APIs this app talks to are stateless — there's no server-side
/// image ID to reference the way the OpenAI Responses API supports. So instead of
/// replaying every image ever shared or generated on every turn (expensive, and
/// ambiguous for the model when several are in play), this picks a bounded default:
/// only the most recently shared/generated image(s) go out at full resolution. Older
/// images are noted as available but omitted (see `ChatRequestHistory`), so the model
/// knows they exist and can ask the user to point at one instead of guessing.
enum ImageContextSelector {
    /// Upper bound on total images included when the user's message signals they
    /// want more than just the latest one (merging, comparing, "all of them", ...).
    static let expandedImageCap = 6

    /// System-prompt section explaining the selection policy above, so the model
    /// doesn't mistake "I wasn't sent that image this turn" for "it doesn't exist."
    static let policyInstruction = """
    Image context: by default, only the most recent image in this conversation \
    (the last one you generated, or the last one the user uploaded) is included with \
    each message — not the full image history. If the user's request clearly involves \
    more than one image (comparing, merging, combining, or explicitly referencing an \
    earlier one), the client includes those too. If you're unsure which image or images \
    the user means, ask a short clarifying question instead of guessing.
    """

    /// Substrings in the latest user message that signal "look further back than
    /// just the most recent image." Intentionally conservative — false negatives
    /// just mean the model asks a clarifying question instead of guessing wrong.
    private static let expansionKeywords: [String] = [
        "both", "all three", "all four", "all of them", "all the images",
        "these images", "those images", "the images", "two images", "three images",
        "multiple images", "each image", "each of these", "each of those",
        "merge", "combine", "combining", "blend", "composite",
        "previous image", "earlier image", "first image", "original image", "last image"
    ]

    /// Whether the latest user message signals it wants more than the single most
    /// recent image considered.
    static func shouldExpand(latestUserText: String) -> Bool {
        let lower = latestUserText.lowercased()
        return expansionKeywords.contains { lower.contains($0) }
    }

    /// Image attachment IDs to include at full fidelity for this turn.
    ///
    /// Always includes every image on the single most recent message that has any
    /// (a user attaching two photos in one message is one unit of "the current
    /// images," not two separate turns). If the latest user message signals it wants
    /// more than that, walks further back message-by-message, up to `expandedImageCap`
    /// images total.
    static func selectedImageIDs(from messages: [ChatMessage]) -> Set<UUID> {
        let latestUserText = messages.last(where: { $0.role == .user })?.content ?? ""
        let expand = shouldExpand(latestUserText: latestUserText)

        var selected: Set<UUID> = []
        var includedAnyMessage = false
        for message in messages.reversed() {
            let images = message.imageAttachments
            guard !images.isEmpty else { continue }

            if !includedAnyMessage {
                selected.formUnion(images.map(\.id))
                includedAnyMessage = true
                continue
            }
            guard expand, selected.count < expandedImageCap else { break }
            selected.formUnion(images.map(\.id))
        }
        return selected
    }
}

import Foundation

/// A single model exposed by a provider, e.g. "deepseek-chat" or "claude-opus-4".
struct AIModel: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    /// Short human hint shown under the model name in the picker, e.g. "128K context · Reasoning".
    var subtitle: String?
    var supportsVision: Bool

    init(id: String, displayName: String, subtitle: String? = nil, supportsVision: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
        self.supportsVision = supportsVision
    }
}

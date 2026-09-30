import Foundation

/// When the chat model may emit fenced memory/rule proposals (cloud tool-capable paths).
enum ChatProposalPolicy {
    /// On-device MLX models cannot reliably follow proposal fence protocols.
    static func allowsModelProposals(usesLocalInference: Bool) -> Bool {
        !usesLocalInference
    }
}

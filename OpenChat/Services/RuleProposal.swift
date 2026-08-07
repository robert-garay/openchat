import Foundation

enum RuleScope: String, Sendable {
    case global
    case chat
}

struct RuleProposal: Equatable, Identifiable, Sendable {
    var id = UUID()
    var content: String
    var scope: RuleScope
}

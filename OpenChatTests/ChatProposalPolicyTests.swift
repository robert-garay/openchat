import XCTest
@testable import OpenChat

final class ChatProposalPolicyTests: XCTestCase {
    func testDisablesProposalsForLocalInference() {
        XCTAssertFalse(ChatProposalPolicy.allowsModelProposals(usesLocalInference: true))
        XCTAssertTrue(ChatProposalPolicy.allowsModelProposals(usesLocalInference: false))
    }
}

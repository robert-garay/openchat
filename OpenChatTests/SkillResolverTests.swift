import XCTest
@testable import OpenChat

final class SkillResolverTests: XCTestCase {
    private let sampleSkills: [SkillMatchable] = [
        SkillMatchable(slashName: "fitness-review", name: "Fitness Review", instructions: "Analyze workouts."),
        SkillMatchable(slashName: "summarize", name: "Summarize", instructions: "Be concise."),
    ]

    func testNormalizeSlashName() {
        XCTAssertEqual(SkillResolver.normalizeSlashName("/Fitness Review"), "fitnessreview")
        XCTAssertEqual(SkillResolver.normalizeSlashName("Fitness_Review"), "fitness-review")
    }

    func testSlashQuery() {
        XCTAssertEqual(SkillResolver.slashQuery(from: "/fit"), "fit")
        XCTAssertNil(SkillResolver.slashQuery(from: "/fitness-review hello"))
        XCTAssertNil(SkillResolver.slashQuery(from: "/fit\nmore"))
        // Large pastes must not be treated as in-progress slash commands.
        XCTAssertNil(SkillResolver.slashQuery(from: "/" + String(repeating: "a", count: 80)))
    }

    func testFilter() {
        XCTAssertEqual(SkillResolver.filter(sampleSkills, query: "fit").map(\.slashName), ["fitness-review"])
    }

    func testResolveOnSend() {
        let r = SkillResolver.resolve(text: "/fitness-review check workout", skills: sampleSkills)
        XCTAssertEqual(r?.storedMessage, "check workout")
        XCTAssertEqual(r?.skill.instructions, "Analyze workouts.")
    }

    func testApplySelection() {
        XCTAssertEqual(SkillResolver.applySelection(skill: sampleSkills[0], to: "/fit"), "/fitness-review ")
    }
}

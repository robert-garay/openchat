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
        XCTAssertEqual(r?.storedMessage, "/fitness-review check workout")
        XCTAssertEqual(r?.skill.instructions, "Analyze workouts.")
    }

    func testResolveUnknownSlashName() {
        XCTAssertNil(SkillResolver.resolve(text: "/unknown-skill hello", skills: sampleSkills))
    }

    func testApplySelection() {
        XCTAssertEqual(SkillResolver.applySelection(skill: sampleSkills[0], to: "/fit"), "/fitness-review ")
    }

    func testIsReservedSlashName() {
        XCTAssertTrue(SkillResolver.isReservedSlashName("skill-builder"))
        XCTAssertFalse(SkillResolver.isReservedSlashName("fitness-review"))
    }

    func testWithBuiltIns() {
        let all = SkillResolver.withBuiltIns(sampleSkills)
        XCTAssertEqual(all.first?.slashName, SkillResolver.skillBuilderSlashName)
        XCTAssertEqual(all.count, sampleSkills.count + 1)
    }

    func testResolveSkillBuilder() {
        let all = SkillResolver.withBuiltIns(sampleSkills)
        let r = SkillResolver.resolve(text: "/skill-builder", skills: all)
        XCTAssertEqual(r?.skill.slashName, SkillResolver.skillBuilderSlashName)
        XCTAssertEqual(r?.storedMessage, "/skill-builder")
    }
}

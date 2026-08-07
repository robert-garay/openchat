import XCTest
@testable import OpenChat

final class SkillResolverTests: XCTestCase {
    private let sampleSkills: [SkillMatchable] = [
        SkillMatchable(
            slashName: "fitness-review",
            name: "Fitness Review",
            description: "Analyze workout logs and provide feedback.",
            instructions: "Analyze workouts."
        ),
        SkillMatchable(
            slashName: "summarize",
            name: "Summarize",
            description: "Summarize long text into bullet points.",
            instructions: "Be concise."
        ),
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

    func testFilterMatchesName() {
        XCTAssertEqual(SkillResolver.filter(sampleSkills, query: "Fitness").map(\.slashName), ["fitness-review"])
    }

    func testFilterMatchesDescription() {
        XCTAssertEqual(SkillResolver.filter(sampleSkills, query: "bullet").map(\.slashName), ["summarize"])
    }

    func testFilterMatchesAcrossSeparators() {
        XCTAssertEqual(SkillResolver.filter(sampleSkills, query: "fitnessreview").map(\.slashName), ["fitness-review"])
    }

    func testFilterMatchesMultipleTokens() {
        XCTAssertEqual(SkillResolver.filter(sampleSkills, query: "fitness feedback").map(\.slashName), ["fitness-review"])
    }

    func testFilterReturnsAllWhenQueryEmpty() {
        let result = SkillResolver.filter(sampleSkills, query: "")
        XCTAssertEqual(result.map(\.slashName), ["fitness-review", "summarize"])
    }

    func testFilterReturnsEmptyForNoMatch() {
        XCTAssertTrue(SkillResolver.filter(sampleSkills, query: "xyz").isEmpty)
    }

    func testFilterExactMatchSortedFirst() {
        let result = SkillResolver.filter(sampleSkills, query: "summarize").map(\.slashName)
        XCTAssertEqual(result.first, "summarize")
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

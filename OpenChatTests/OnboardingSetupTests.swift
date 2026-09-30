import XCTest
@testable import OpenChat

final class OnboardingSetupTests: XCTestCase {
    private let versionKey = OnboardingSetup.localModelsSetupExperienceVersionKey
    private let completedKey = OnboardingSetup.completedKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: versionKey)
        UserDefaults.standard.removeObject(forKey: completedKey)
        super.tearDown()
    }

    func testNewInstallShowsSetupWhenNotCompleted() {
        UserDefaults.standard.set(false, forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: versionKey)
        XCTAssertTrue(OnboardingSetup.shouldPresentSetup(setupCompleted: false))
    }

    func testUpdateUserSeesSetupOnceAfterFeatureVersionBump() {
        UserDefaults.standard.set(true, forKey: completedKey)
        UserDefaults.standard.set(0, forKey: versionKey)
        XCTAssertTrue(OnboardingSetup.shouldPresentSetup(setupCompleted: true))

        OnboardingSetup.markLocalModelsSetupExperienceSeen()
        XCTAssertFalse(OnboardingSetup.shouldPresentSetup(setupCompleted: true))
    }

    func testCompletedNewInstallAfterMarkingExperience() {
        UserDefaults.standard.set(true, forKey: completedKey)
        OnboardingSetup.markLocalModelsSetupExperienceSeen()
        XCTAssertFalse(OnboardingSetup.shouldPresentSetup(setupCompleted: true))
    }
}

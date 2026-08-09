import HealthKit
@preconcurrency import XCTest
@testable import OpenChat

@MainActor
final class AgentDataSourceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: AgentDataSourceStore!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "com.openchat.tests.datasources.\(UUID().uuidString)")
        store = AgentDataSourceStore(defaults: defaults)
    }

    func testDefaultsToAllDisabled() {
        XCTAssertEqual(store.enabledCount, 0)
        XCTAssertFalse(store.hasAcknowledgedFitnessPrivacyNotice)
        for source in AgentDataSource.allCases {
            XCTAssertFalse(store.isEnabled(source))
            XCTAssertFalse(store.isAvailableForAgents(source))
        }
    }

    func testLoadsPersistedEnabledSourcesAndDropsRemovedOnes() {
        defaults.set(["appleHealth", "calendar", "home"], forKey: "com.openchat.agentDataSources")
        store = AgentDataSourceStore(defaults: defaults)

        XCTAssertTrue(store.isEnabled(.appleHealth))
        XCTAssertTrue(store.isEnabled(.calendar))
        XCTAssertEqual(store.enabledCount, 2)
        XCTAssertEqual(Set(store.enabledSources.map(\.rawValue)), ["appleHealth", "calendar"])
        XCTAssertTrue(defaults.bool(forKey: "com.openchat.healthAuthPromptCompleted"))
        // Health read grants are opaque; an enabled Health toggle is enough for agent access
        // whenever HealthKit exists on the device.
        if HKHealthStore.isHealthDataAvailable() {
            XCTAssertTrue(store.isAvailableForAgents(.appleHealth))
        }

        let persisted = defaults.array(forKey: "com.openchat.agentDataSources") as? [String] ?? []
        XCTAssertFalse(persisted.contains("home"))
    }

    func testEnabledHealthIsAvailableEvenWithoutCachedAuthorizedStatus() {
        defaults.set(["appleHealth"], forKey: "com.openchat.agentDataSources")
        store = AgentDataSourceStore(defaults: defaults)
        store.refreshAuthorizationStatuses()

        XCTAssertTrue(store.isEnabled(.appleHealth))
        if HKHealthStore.isHealthDataAvailable() {
            XCTAssertTrue(store.isAvailableForAgents(.appleHealth))
        } else {
            XCTAssertFalse(store.isAvailableForAgents(.appleHealth))
        }
    }

    func testDisablingClearsPersistence() async {
        defaults.set(["photos"], forKey: "com.openchat.agentDataSources")
        store = AgentDataSourceStore(defaults: defaults)
        XCTAssertTrue(store.isEnabled(.photos))

        await store.setEnabled(false, for: .photos)

        XCTAssertFalse(store.isEnabled(.photos))
        let persisted = defaults.array(forKey: "com.openchat.agentDataSources") as? [String] ?? []
        XCTAssertFalse(persisted.contains("photos"))
    }

    func testHealthRequiresFitnessPrivacyNoticeBeforeEnable() async {
        let status = await store.setEnabled(true, for: .appleHealth)
        XCTAssertEqual(status, .notDetermined)
        XCTAssertFalse(store.isEnabled(.appleHealth))

        store.acknowledgeFitnessPrivacyNotice()
        XCTAssertTrue(store.hasAcknowledgedFitnessPrivacyNotice)
        XCTAssertTrue(defaults.bool(forKey: "com.openchat.fitnessPrivacyNoticeAcknowledged"))
    }

    func testSectionsCoverEverySourceExactlyOnce() {
        let grouped = AgentDataSourceSection.allCases.flatMap(\.sources)
        XCTAssertEqual(Set(grouped.map(\.rawValue)), Set(AgentDataSource.allCases.map(\.rawValue)))
        XCTAssertEqual(grouped.count, AgentDataSource.allCases.count)
    }

    func testMVPSourceSet() {
        let ids = Set(AgentDataSource.allCases.map(\.rawValue))
        XCTAssertEqual(ids, [
            "appleHealth",
            "camera",
            "microphone",
            "photos",
            "contacts",
            "calendar",
            "reminders",
            "notifications",
        ])
    }

    func testRemindersModeDefaultsNilAndClearsOnDisable() async {
        XCTAssertNil(store.remindersAccessMode)
        store.markAvailableForTesting(.reminders, remindersMode: .readWrite)
        XCTAssertEqual(store.remindersAccessMode, .readWrite)
        XCTAssertTrue(store.canEditReminders)

        await store.setEnabled(false, for: .reminders)
        XCTAssertNil(store.remindersAccessMode)
        XCTAssertFalse(store.canEditReminders)
    }

    func testPersistedReadOnlyRemindersMode() {
        defaults.set(["reminders"], forKey: "com.openchat.agentDataSources")
        defaults.set(RemindersAccessMode.readOnly.rawValue, forKey: "com.openchat.remindersAccessMode")
        store = AgentDataSourceStore(defaults: defaults)

        XCTAssertTrue(store.isEnabled(.reminders))
        XCTAssertEqual(store.remindersAccessMode, .readOnly)
        XCTAssertFalse(store.canEditReminders)
    }

    func testContactsHasNoAccessModeButCanEditWhenEnabled() {
        XCTAssertFalse(store.canEditContacts)
        store.markAvailableForTesting(.contacts)
        XCTAssertTrue(store.isEnabled(.contacts))
        XCTAssertTrue(store.canEditContacts)
    }

    func testFitnessHealthAllowlistExcludesBodyMetricsAndIsWorkoutFocused() {
        let ids = Set(FitnessHealthDataTypes.quantityIdentifiers.map(\.rawValue))
        XCTAssertEqual(ids, [
            "HKQuantityTypeIdentifierStepCount",
            "HKQuantityTypeIdentifierHeartRate",
            "HKQuantityTypeIdentifierRestingHeartRate",
            "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
            "HKQuantityTypeIdentifierActiveEnergyBurned",
            "HKQuantityTypeIdentifierAppleExerciseTime",
            "HKQuantityTypeIdentifierDistanceWalkingRunning",
        ])
        XCTAssertFalse(ids.contains("HKQuantityTypeIdentifierBodyMass"))
        XCTAssertFalse(ids.contains("HKQuantityTypeIdentifierHeight"))
        XCTAssertFalse(ids.contains("HKQuantityTypeIdentifierBloodGlucose"))

        let readTypes = FitnessHealthDataTypes.readTypes
        XCTAssertTrue(readTypes.contains(HKObjectType.workoutType()))
        XCTAssertTrue(readTypes.contains(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!))
        XCTAssertFalse(readTypes.contains(where: { $0 is HKClinicalType }))
    }
}

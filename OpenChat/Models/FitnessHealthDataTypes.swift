import HealthKit

/// Strict allowlist of Apple Health types OpenChat may request for fitness coaching.
/// Clinical records, labs, medications, and other medical datasets are never included.
enum FitnessHealthDataTypes {
    /// Quantity samples used for workout / activity insights.
    static let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
        .stepCount,
        .heartRate,
        .restingHeartRate,
        .heartRateVariabilitySDNN,
        .activeEnergyBurned,
        .appleExerciseTime,
        .distanceWalkingRunning,
    ]

    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        for id in quantityIdentifiers {
            if let type = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }
        // Sleep supports recovery coaching; still fitness-adjacent, not clinical records.
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    static let userFacingSummary =
        "steps, heart rate, resting heart rate, HRV, active energy, exercise minutes, walking/running distance, sleep, and workouts"
}

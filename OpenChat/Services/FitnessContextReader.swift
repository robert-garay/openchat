import Foundation
import HealthKit

/// Reads opted-in fitness HealthKit samples for agent context.
enum FitnessContextReader {
    static func contextSection(now: Date = .now, calendar: Calendar = .current) async -> String? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let store = HKHealthStore()
        let dayStart = calendar.startOfDay(for: now)

        async let steps = statisticSum(
            store: store,
            identifier: .stepCount,
            unit: .count(),
            start: dayStart,
            end: now
        )
        async let energy = statisticSum(
            store: store,
            identifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            start: dayStart,
            end: now
        )
        async let exercise = statisticSum(
            store: store,
            identifier: .appleExerciseTime,
            unit: .minute(),
            start: dayStart,
            end: now
        )
        async let distance = statisticSum(
            store: store,
            identifier: .distanceWalkingRunning,
            unit: .mile(),
            start: dayStart,
            end: now
        )
        async let workouts = recentWorkouts(store: store, now: now, calendar: calendar)
        async let sleepHours = lastNightSleepHours(store: store, now: now, calendar: calendar)

        let stepsValue = await steps
        let energyValue = await energy
        let exerciseValue = await exercise
        let distanceValue = await distance
        let workoutRows = await workouts
        let sleepValue = await sleepHours

        var lines: [String] = ["## Fitness (Apple Health)"]
        if let stepsValue {
            lines.append("- Steps today: \(Int(stepsValue.rounded()))")
        }
        if let energyValue {
            lines.append("- Active energy today: \(Int(energyValue.rounded())) kcal")
        }
        if let exerciseValue {
            lines.append("- Exercise minutes today: \(Int(exerciseValue.rounded()))")
        }
        if let distanceValue {
            lines.append(String(format: "- Walking/running distance today: %.1f mi", distanceValue))
        }
        if let sleepValue {
            lines.append(String(format: "- Sleep (last night): %.1f hours", sleepValue))
        }

        if workoutRows.isEmpty {
            lines.append("- Recent workouts: none in the last 7 days")
        } else {
            lines.append("- Recent workouts:")
            lines.append(contentsOf: workoutRows.map { "  - \($0)" })
        }

        // If HealthKit returned nothing usable, skip injecting an empty section.
        guard lines.count > 1 else { return nil }
        return lines.joined(separator: "\n")
    }

    private static func statisticSum(
        store: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private static func recentWorkouts(
        store: HKHealthStore,
        now: Date,
        calendar: Calendar
    ) async -> [String] {
        guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let samples: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 5,
                sortDescriptors: [sort]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .medium
        dayFormatter.timeStyle = .short

        return samples.map { workout in
            let minutes = Int((workout.duration / 60.0).rounded())
            let name = workout.workoutActivityType.name
            let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
            if let calories {
                return "\(dayFormatter.string(from: workout.startDate)): \(name), \(minutes) min, \(Int(calories.rounded())) kcal"
            }
            return "\(dayFormatter.string(from: workout.startDate)): \(name), \(minutes) min"
        }
    }

    private static func lastNightSleepHours(
        store: HKHealthStore,
        now: Date,
        calendar: Calendar
    ) async -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        guard let windowStart = calendar.date(byAdding: .hour, value: -36, to: now) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: now, options: .strictStartDate)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]

        let totalSeconds = samples
            .filter { asleepValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

        guard totalSeconds > 0 else { return nil }
        return totalSeconds / 3600.0
    }
}

private extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .hiking: "Hiking"
        case .yoga: "Yoga"
        case .traditionalStrengthTraining: "Strength training"
        case .functionalStrengthTraining: "Functional strength"
        case .highIntensityIntervalTraining: "HIIT"
        case .elliptical: "Elliptical"
        case .rowing: "Rowing"
        case .dance: "Dance"
        case .cooldown: "Cooldown"
        case .coreTraining: "Core training"
        case .flexibility: "Flexibility"
        case .mixedCardio: "Mixed cardio"
        case .other: "Workout"
        @unknown default: "Workout"
        }
    }
}

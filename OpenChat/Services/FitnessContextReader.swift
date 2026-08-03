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
        async let averageHeartRate = statisticAverage(
            store: store,
            identifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: dayStart,
            end: now
        )
        async let restingHeartRate = latestQuantity(
            store: store,
            identifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let hrv = latestQuantity(
            store: store,
            identifier: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli)
        )
        async let workouts = recentWorkouts(store: store, now: now, calendar: calendar)
        async let sleepHours = lastNightSleepHours(store: store, now: now, calendar: calendar)

        let stepsValue = await steps
        let energyValue = await energy
        let exerciseValue = await exercise
        let distanceValue = await distance
        let heartRateValue = await averageHeartRate
        let restingValue = await restingHeartRate
        let hrvValue = await hrv
        let workoutRows = await workouts
        let sleepValue = await sleepHours

        var lines: [String] = [
            "## Fitness (Apple Health)",
            "Use these metrics when the user asks about steps, heart rate, workouts, sleep, or training. If a metric says unavailable, say you don't have that reading — do not invent values.",
        ]

        lines.append(metricLine("Steps today", stepsValue.map { "\(Int($0.rounded()))" }))
        lines.append(metricLine("Active energy today", energyValue.map { "\(Int($0.rounded())) kcal" }))
        lines.append(metricLine("Exercise minutes today", exerciseValue.map { "\(Int($0.rounded()))" }))
        lines.append(metricLine(
            "Walking/running distance today",
            distanceValue.map { String(format: "%.1f mi", $0) }
        ))
        lines.append(metricLine(
            "Average heart rate today",
            heartRateValue.map { "\(Int($0.rounded())) bpm" }
        ))
        lines.append(metricLine(
            "Resting heart rate (latest)",
            restingValue.map { "\(Int($0.rounded())) bpm" }
        ))
        lines.append(metricLine(
            "Heart rate variability SDNN (latest)",
            hrvValue.map { String(format: "%.0f ms", $0) }
        ))
        lines.append(metricLine(
            "Sleep (last night)",
            sleepValue.map { String(format: "%.1f hours", $0) }
        ))

        if workoutRows.isEmpty {
            lines.append("- Recent workouts: none in the last 7 days")
        } else {
            lines.append("- Recent workouts:")
            lines.append(contentsOf: workoutRows.map { "  - \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private static func metricLine(_ label: String, _ value: String?) -> String {
        "- \(label): \(value ?? "unavailable")"
    }

    private static func statisticSum(
        store: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        await statistic(store: store, identifier: identifier, unit: unit, start: start, end: end, options: .cumulativeSum) {
            $0.sumQuantity()?.doubleValue(for: unit)
        }
    }

    private static func statisticAverage(
        store: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        await statistic(store: store, identifier: identifier, unit: unit, start: start, end: end, options: .discreteAverage) {
            $0.averageQuantity()?.doubleValue(for: unit)
        }
    }

    private static func statistic(
        store: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date,
        options: HKStatisticsOptions,
        extract: @escaping (HKStatistics) -> Double?
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, statistics, _ in
                guard let statistics else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: extract(statistics))
            }
            store.execute(query)
        }
    }

    private static func latestQuantity(
        store: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let sample: HKQuantitySample? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, results, _ in
                continuation.resume(returning: results?.first as? HKQuantitySample)
            }
            store.execute(query)
        }

        return sample?.quantity.doubleValue(for: unit)
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

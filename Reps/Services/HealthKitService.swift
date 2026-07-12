import Foundation
import HealthKit

/// Single read surface for external data. FitDays (the BLE scale app) pushes
/// weight, BMI, body-fat %, and lean mass into Apple Health via its System
/// Permission screen; Apple Activity writes the rings. Reps reads both here.
/// Weigh-ins are sparse (every few days), so queries are "latest on/before"
/// rather than strict same-day.
@MainActor
enum HealthKitService {
    private static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// The body-composition types FitDays can write to Apple Health.
    private static var bodyTypes: Set<HKQuantityType> {
        [
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyMassIndex),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.leanBodyMass),
        ]
    }

    static func requestAuthorization() async throws {
        var read: Set<HKObjectType> = bodyTypes
        read.insert(HKQuantityType(.stepCount))
        read.insert(HKObjectType.activitySummaryType())
        try await store.requestAuthorization(toShare: [], read: read)
    }

    // MARK: - Weigh-ins (batch, for backfilling correct days)

    /// Every weigh-in since `start` (default: all history), keyed to the
    /// calendar day it happened. FitDays writes weight/BMI/fat/lean at one
    /// timestamp per session, so we fetch each series once and stitch by day.
    static func weighIns(since start: Date = .distantPast) async -> [(day: Date, metrics: BodyMetrics)] {
        let end = Date()

        let weights = await samples(.bodyMass, unit: .pound(), start: start, end: end)
        guard !weights.isEmpty else { return [] }
        let bmis = byDay(await samples(.bodyMassIndex, unit: .count(), start: start, end: end))
        let fats = byDay(await samples(.bodyFatPercentage, unit: .percent(), start: start, end: end))
        let leans = byDay(await samples(.leanBodyMass, unit: .pound(), start: start, end: end))

        // One weigh-in per day (the latest that day).
        var latestPerDay: [Date: (date: Date, value: Double)] = [:]
        for w in weights {
            let day = Calendar.current.startOfDay(for: w.date)
            if let existing = latestPerDay[day], existing.date >= w.date { continue }
            latestPerDay[day] = w
        }

        return latestPerDay.keys.sorted().map { day in
            let w = latestPerDay[day]!
            let metrics = BodyMetrics(
                weightLbs: round1(w.value),
                bmi: bmis[day].map { round1($0) },
                bodyFatPct: fats[day].map { round1($0 * 100) },      // 0.179 → 17.9
                leanMassLbs: leans[day].map { round1($0) },
                measuredAt: w.date
            )
            return (day, metrics)
        }
    }

    // MARK: - Activity

    static func activity(for day: Date) async -> ActivitySummary? {
        let summary = await activitySummary(for: day)
        let steps = await stepCount(for: day)
        guard summary != nil || steps != nil else { return nil }
        var result = summary ?? ActivitySummary(moveKcal: 0, exerciseMin: 0, standHours: 0)
        result.steps = steps
        return result
    }

    private static func activitySummary(for day: Date) async -> ActivitySummary? {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.calendar = Calendar.current
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: components, end: components)
        return await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                guard let s = summaries?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let goalMove = s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                let result = ActivitySummary(
                    moveKcal: Int(s.activeEnergyBurned.doubleValue(for: .kilocalorie())),
                    moveGoalKcal: goalMove > 0 ? Int(goalMove) : 500,
                    exerciseMin: Int(s.appleExerciseTime.doubleValue(for: .minute())),
                    exerciseGoalMin: Int(max(s.appleExerciseTimeGoal.doubleValue(for: .minute()), 1)),
                    standHours: Int(s.appleStandHours.doubleValue(for: .count())),
                    standGoalHours: Int(max(s.appleStandHoursGoal.doubleValue(for: .count()), 1))
                )
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private static func stepCount(for day: Date) async -> Int? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.stepCount),
                quantitySamplePredicate: dayPredicate(day),
                options: .cumulativeSum
            ) { _, stats, _ in
                guard let sum = stats?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Int(sum.doubleValue(for: .count())))
            }
            store.execute(query)
        }
    }

    // MARK: - Sample plumbing

    private static func samples(
        _ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date
    ) async -> [(date: Date, value: Double)] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(id), predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, _ in
                let mapped = (samples as? [HKQuantitySample] ?? []).map {
                    (date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    /// Latest value per calendar day.
    private static func byDay(_ samples: [(date: Date, value: Double)]) -> [Date: Double] {
        var result: [Date: (date: Date, value: Double)] = [:]
        for s in samples {
            let day = Calendar.current.startOfDay(for: s.date)
            if let existing = result[day], existing.date >= s.date { continue }
            result[day] = s
        }
        return result.mapValues(\.value)
    }

    private static func dayPredicate(_ day: Date) -> NSPredicate {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? day
        return HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
    }

    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}

#if DEBUG
extension HealthKitService {
    /// Writes a few realistic weigh-ins to Apple Health so the HealthKit →
    /// vault → display path can be exercised in the simulator (no scale there).
    /// Mirrors the FitDays screenshots: ~128 lb, BMI 19.5, ~18% fat.
    static func seedSampleWeighIns() async throws {
        try await store.requestAuthorization(toShare: bodyTypes, read: bodyTypes)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        // (daysAgo, weight, bmi, fatFraction, lean)
        let points: [(Int, Double, Double, Double, Double)] = [
            (11, 129.2, 19.6, 0.184, 99.1),
            (8, 128.4, 19.5, 0.182, 99.0),
            (5, 129.4, 19.6, 0.181, 99.2),
            (2, 128.1, 19.5, 0.179, 99.0),
            (1, 128.4, 19.5, 0.179, 99.1),
        ]
        for (daysAgo, weight, bmi, fat, lean) in points {
            let when = cal.date(byAdding: .hour, value: 8,
                                to: cal.date(byAdding: .day, value: -daysAgo, to: today)!)!
            let samples: [HKQuantitySample] = [
                .init(type: HKQuantityType(.bodyMass),
                      quantity: .init(unit: .pound(), doubleValue: weight), start: when, end: when),
                .init(type: HKQuantityType(.bodyMassIndex),
                      quantity: .init(unit: .count(), doubleValue: bmi), start: when, end: when),
                .init(type: HKQuantityType(.bodyFatPercentage),
                      quantity: .init(unit: .percent(), doubleValue: fat), start: when, end: when),
                .init(type: HKQuantityType(.leanBodyMass),
                      quantity: .init(unit: .pound(), doubleValue: lean), start: when, end: when),
            ]
            try await store.save(samples)
        }
    }
}
#endif

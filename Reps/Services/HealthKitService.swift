import Foundation
import HealthKit

/// Single read surface for external data: Apple Activity rings and the
/// FitDays scale (which syncs weight/body-comp into Apple Health).
@MainActor
enum HealthKitService {
    private static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static func requestAuthorization() async throws {
        let types: Set<HKObjectType> = [
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.leanBodyMass),
            HKQuantityType(.stepCount),
            HKObjectType.activitySummaryType(),
        ]
        try await store.requestAuthorization(toShare: [], read: types)
    }

    // MARK: - Body metrics

    static func metrics(for day: Date) async -> BodyMetrics? {
        let weight = await latestQuantity(.bodyMass, unit: .pound(), on: day)
        guard let weight else { return nil }
        let bodyFat = await latestQuantity(.bodyFatPercentage, unit: .percent(), on: day)
        let leanMass = await latestQuantity(.leanBodyMass, unit: .pound(), on: day)
        return BodyMetrics(
            weightLbs: (weight.value * 10).rounded() / 10,
            bodyFatPct: bodyFat.map { ($0.value * 1000).rounded() / 10 }, // 0.254 → 25.4
            leanMassLbs: leanMass.map { ($0.value * 10).rounded() / 10 },
            measuredAt: weight.date
        )
    }

    private static func latestQuantity(
        _ id: HKQuantityTypeIdentifier, unit: HKUnit, on day: Date
    ) async -> (value: Double, date: Date)? {
        let type = HKQuantityType(id)
        let predicate = dayPredicate(day)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (sample.quantity.doubleValue(for: unit), sample.startDate))
            }
            store.execute(query)
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
                let result = ActivitySummary(
                    moveKcal: Int(s.activeEnergyBurned.doubleValue(for: .kilocalorie())),
                    moveGoalKcal: Int(s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())),
                    exerciseMin: Int(s.appleExerciseTime.doubleValue(for: .minute())),
                    exerciseGoalMin: Int(s.appleExerciseTimeGoal.doubleValue(for: .minute())),
                    standHours: Int(s.appleStandHours.doubleValue(for: .count())),
                    standGoalHours: Int(s.appleStandHoursGoal.doubleValue(for: .count()))
                )
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private static func stepCount(for day: Date) async -> Int? {
        return await withCheckedContinuation { continuation in
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

    private static func dayPredicate(_ day: Date) -> NSPredicate {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? day
        return HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
    }
}

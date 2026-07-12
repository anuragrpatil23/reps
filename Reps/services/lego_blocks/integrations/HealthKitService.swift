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

    /// Apple Health quantity series charted on the Trends tab.
    private static var activityTypes: Set<HKQuantityType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.restingHeartRate),
        ]
    }

    /// Curated vitals we chart + export to heart.csv / respiratory.csv.
    private static var vitalsTypes: Set<HKQuantityType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.walkingHeartRateAverage),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.vo2Max),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.appleSleepingWristTemperature),
        ]
    }

    /// ~7 years — covers an Apple Watch owned since 2019.
    static let fullHistoryDays = 2600

    static func requestAuthorization() async throws {
        var read: Set<HKObjectType> = bodyTypes
        read.formUnion(activityTypes)
        read.formUnion(vitalsTypes)
        read.insert(HKObjectType.activitySummaryType())
        read.insert(HKCategoryType(.sleepAnalysis))
        read.insert(HKObjectType.workoutType())
        try await store.requestAuthorization(toShare: [], read: read)
    }

    // MARK: - Vitals (heart.csv / respiratory.csv)

    enum Reduction { case sum, average, min, max }

    /// One reduced value per day for `days` back.
    private static func dailyMap(
        _ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int, _ reduce: Reduction
    ) async -> [Date: Double] {
        let options: HKStatisticsOptions = switch reduce {
        case .sum: .cumulativeSum
        case .average: .discreteAverage
        case .min: .discreteMin
        case .max: .discreteMax
        }
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: anchor) ?? anchor
        let start = cal.date(byAdding: .day, value: -days, to: anchor) ?? anchor
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: HKQuantityType(id),
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: options, anchorDate: anchor, intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                var result: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { stat, _ in
                    let quantity: HKQuantity? = switch reduce {
                    case .sum: stat.sumQuantity()
                    case .average: stat.averageQuantity()
                    case .min: stat.minimumQuantity()
                    case .max: stat.maximumQuantity()
                    }
                    if let quantity {
                        result[cal.startOfDay(for: stat.startDate)] = quantity.doubleValue(for: unit)
                    }
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    static func heartDaily(days: Int) async -> [Date: [String: Double]] {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let avg = await dailyMap(.heartRate, unit: bpm, days: days, .average)
        let lo = await dailyMap(.heartRate, unit: bpm, days: days, .min)
        let hi = await dailyMap(.heartRate, unit: bpm, days: days, .max)
        let walking = await dailyMap(.walkingHeartRateAverage, unit: bpm, days: days, .average)
        let hrv = await dailyMap(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), days: days, .average)
        let vo2 = await dailyMap(.vo2Max, unit: HKUnit(from: "ml/kg*min"), days: days, .average)
        return mergeColumns([
            "avg_hr": avg, "min_hr": lo, "max_hr": hi,
            "walking_hr": walking, "hrv_sdnn": hrv, "vo2max": vo2,
        ])
    }

    static func respiratoryDaily(days: Int) async -> [Date: [String: Double]] {
        let spo2Avg = (await dailyMap(.oxygenSaturation, unit: .percent(), days: days, .average)).mapValues { $0 * 100 }
        let spo2Min = (await dailyMap(.oxygenSaturation, unit: .percent(), days: days, .min)).mapValues { $0 * 100 }
        let respRate = await dailyMap(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), days: days, .average)
        let wristTemp = await dailyMap(.appleSleepingWristTemperature, unit: .degreeCelsius(), days: days, .average)
        return mergeColumns([
            "spo2_avg": spo2Avg, "spo2_min": spo2Min,
            "respiratory_rate": respRate, "wrist_temp_c": wristTemp,
        ])
    }

    private static func mergeColumns(_ columns: [String: [Date: Double]]) -> [Date: [String: Double]] {
        var result: [Date: [String: Double]] = [:]
        for (name, series) in columns {
            for (day, value) in series {
                result[day, default: [:]][name] = (value * 10).rounded() / 10
            }
        }
        return result
    }

    // MARK: - Sleep (sleep.csv)

    /// Nightly minutes by stage, keyed to the wake-up date (sample end day).
    static func sleepDaily(days: Int) async -> [Date: [String: Double]] {
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                var result: [Date: [String: Double]] = [:]
                for case let s as HKCategorySample in samples ?? [] {
                    let day = cal.startOfDay(for: s.endDate)
                    let minutes = s.endDate.timeIntervalSince(s.startDate) / 60
                    let column: String? = switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
                    case .inBed: "in_bed_min"
                    case .awake: "awake_min"
                    case .asleepREM: "rem_min"
                    case .asleepCore: "core_min"
                    case .asleepDeep: "deep_min"
                    case .asleepUnspecified: "asleep_min"
                    default: nil
                    }
                    guard let column else { continue }
                    result[day, default: [:]][column, default: 0] += minutes
                    // Stage samples also roll up into total asleep.
                    if column != "in_bed_min" && column != "awake_min" && column != "asleep_min" {
                        result[day, default: [:]]["asleep_min", default: 0] += minutes
                    }
                }
                for day in result.keys {
                    result[day] = result[day]?.mapValues { $0.rounded() }
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    // MARK: - Workouts (workouts.csv)

    static func workoutHistory(days: Int) async -> [WorkoutRecord] {
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(), predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                let records = (samples as? [HKWorkout] ?? []).map { w -> WorkoutRecord in
                    let energy = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                        .sumQuantity()?.doubleValue(for: .kilocalorie())
                    let distance = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                        .sumQuantity()?.doubleValue(for: .mile())
                    let hr = w.statistics(for: HKQuantityType(.heartRate))?
                        .averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    return WorkoutRecord(
                        start: w.startDate,
                        type: workoutTypeName(w.workoutActivityType),
                        durationMin: (w.duration / 60 * 10).rounded() / 10,
                        energyKcal: energy.map { ($0).rounded() },
                        distanceMi: distance.map { ($0 * 100).rounded() / 100 },
                        avgHR: hr.map { ($0).rounded() }
                    )
                }
                continuation.resume(returning: records)
            }
            store.execute(query)
        }
    }

    private static func workoutTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .hiking: "Hiking"
        case .traditionalStrengthTraining: "Strength"
        case .functionalStrengthTraining: "Functional strength"
        case .highIntensityIntervalTraining: "HIIT"
        case .coreTraining: "Core"
        case .yoga: "Yoga"
        case .elliptical: "Elliptical"
        case .rowing: "Rowing"
        case .swimming: "Swimming"
        case .stairClimbing, .stairs: "Stairs"
        case .pilates: "Pilates"
        case .cooldown: "Cooldown"
        default: "Other"
        }
    }

    // MARK: - Daily statistics series (Apple Health charts)

    /// One value per day for `days` back — cumulative sum (steps, energy,
    /// exercise) or discrete average (resting HR). Empty days are dropped.
    static func dailySeries(
        _ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int, options: HKStatisticsOptions
    ) async -> [MetricPoint] {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: anchor) ?? anchor
        let start = cal.date(byAdding: .day, value: -days, to: anchor) ?? anchor
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: HKQuantityType(id),
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: options,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                var points: [MetricPoint] = []
                collection?.enumerateStatistics(from: start, to: end) { stat, _ in
                    let quantity = options.contains(.cumulativeSum)
                        ? stat.sumQuantity() : stat.averageQuantity()
                    if let quantity {
                        let value = quantity.doubleValue(for: unit)
                        if value > 0 { points.append(MetricPoint(date: stat.startDate, value: value)) }
                    }
                }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
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

    // MARK: - Activity history (for the activity CSV)

    /// Per-day activity for `days` back: rings + goals from Activity summaries,
    /// merged with steps and resting HR. Only days with some data are returned.
    static func activityHistory(days: Int) async -> [Date: ActivitySummary] {
        var byDay = await activitySummaries(days: days)
        let cal = Calendar.current
        for point in await dailySeries(.stepCount, unit: .count(), days: days, options: .cumulativeSum) {
            let day = cal.startOfDay(for: point.date)
            byDay[day, default: ActivitySummary(moveKcal: 0, exerciseMin: 0, standHours: 0)].steps = Int(point.value)
        }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        for point in await dailySeries(.restingHeartRate, unit: bpm, days: days, options: .discreteAverage) {
            let day = cal.startOfDay(for: point.date)
            byDay[day, default: ActivitySummary(moveKcal: 0, exerciseMin: 0, standHours: 0)].restingHR = Int(point.value.rounded())
        }
        return byDay
    }

    private static func activitySummaries(days: Int) async -> [Date: ActivitySummary] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -days, to: end) ?? end
        var startComp = cal.dateComponents([.year, .month, .day], from: start)
        startComp.calendar = cal
        var endComp = cal.dateComponents([.year, .month, .day], from: end)
        endComp.calendar = cal
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: startComp, end: endComp)
        return await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                var result: [Date: ActivitySummary] = [:]
                for s in summaries ?? [] {
                    guard let date = s.dateComponents(for: cal).date else { continue }
                    let goalMove = s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                    result[cal.startOfDay(for: date)] = ActivitySummary(
                        moveKcal: Int(s.activeEnergyBurned.doubleValue(for: .kilocalorie())),
                        moveGoalKcal: goalMove > 0 ? Int(goalMove) : 500,
                        exerciseMin: Int(s.appleExerciseTime.doubleValue(for: .minute())),
                        exerciseGoalMin: Int(max(s.appleExerciseTimeGoal.doubleValue(for: .minute()), 1)),
                        standHours: Int(s.appleStandHours.doubleValue(for: .count())),
                        standGoalHours: Int(max(s.appleStandHoursGoal.doubleValue(for: .count()), 1))
                    )
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    // MARK: - Activity (single day, for the Today rings)

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
        try await store.requestAuthorization(toShare: bodyTypes.union(activityTypes), read: bodyTypes)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        // Sparse weigh-ins trending down over ~90 days.
        for daysAgo in stride(from: 90, through: 0, by: -3) {
            let frac = Double(90 - daysAgo) / 90
            let weight = 142.0 - 4.0 * frac + Double.random(in: -0.4...0.4)
            let fat = 0.254 - 0.016 * frac + Double.random(in: -0.002...0.002)
            let bmi = 21.0 - 0.6 * frac
            let lean = weight * (1 - fat)
            let when = cal.date(byAdding: .hour, value: 8,
                                to: cal.date(byAdding: .day, value: -daysAgo, to: today)!)!
            try await store.save([
                HKQuantitySample(type: HKQuantityType(.bodyMass),
                    quantity: .init(unit: .pound(), doubleValue: weight), start: when, end: when),
                HKQuantitySample(type: HKQuantityType(.bodyMassIndex),
                    quantity: .init(unit: .count(), doubleValue: bmi), start: when, end: when),
                HKQuantitySample(type: HKQuantityType(.bodyFatPercentage),
                    quantity: .init(unit: .percent(), doubleValue: fat), start: when, end: when),
                HKQuantitySample(type: HKQuantityType(.leanBodyMass),
                    quantity: .init(unit: .pound(), doubleValue: lean), start: when, end: when),
            ])
        }

        // Daily activity for the last 60 days so the Apple Health charts render.
        for daysAgo in stride(from: 60, through: 0, by: -1) {
            guard let dayStart = cal.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let mid = cal.date(byAdding: .hour, value: 14, to: dayStart)!
            let end = cal.date(byAdding: .minute, value: 30, to: mid)!
            let steps = Double.random(in: 5000...12000)
            let energy = Double.random(in: 350...650)
            let exercise = Double.random(in: 15...55)
            let rhr = Double.random(in: 52...61)
            try await store.save([
                HKQuantitySample(type: HKQuantityType(.stepCount),
                    quantity: .init(unit: .count(), doubleValue: steps), start: mid, end: end),
                HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                    quantity: .init(unit: .kilocalorie(), doubleValue: energy), start: mid, end: end),
                HKQuantitySample(type: HKQuantityType(.appleExerciseTime),
                    quantity: .init(unit: .minute(), doubleValue: exercise), start: mid, end: end),
                HKQuantitySample(type: HKQuantityType(.restingHeartRate),
                    quantity: .init(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: rhr),
                    start: mid, end: end),
            ])
        }
    }
}
#endif

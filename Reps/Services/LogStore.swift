import Foundation
import SwiftUI

/// The app's single observable store. In-memory cache over the vault files —
/// rebuildable from a folder rescan at any time (contract §6), so losing it
/// costs nothing. All writes go file-first through VaultStore.
@MainActor
@Observable
final class LogStore {
    let vault = VaultStore()

    private(set) var logsByDay: [Date: DailyLog] = [:]
    private(set) var templates: [WorkoutTemplate] = []
    private(set) var loaded = false
    var lastError: String?

    var vaultConfigured: Bool { vault.isConfigured }

    // MARK: - Load / rebuild

    func load() {
        logsByDay = [:]
        for date in vault.listLogDates() {
            if let log = vault.readDailyLog(for: date) {
                logsByDay[Calendar.current.startOfDay(for: date)] = log
            }
        }
        let fromVault = vault.readTemplates()
        templates = fromVault.isEmpty ? [.builtinPushA] : fromVault
        loaded = true
    }

    func connectVault(to url: URL) {
        do {
            try vault.setRoot(url)
            load()
        } catch {
            lastError = "Couldn't save vault folder access: \(error.localizedDescription)"
        }
    }

    // MARK: - Reads

    func log(for date: Date) -> DailyLog? {
        logsByDay[Calendar.current.startOfDay(for: date)]
    }

    /// Most recent weigh-in on or before `date` — for carry-forward display,
    /// since the scale only runs every few days.
    func recentMetrics(asOf date: Date) -> (metrics: BodyMetrics, day: Date)? {
        let target = Calendar.current.startOfDay(for: date)
        let latest = logsByDay.values
            .filter { $0.date <= target && $0.metrics != nil }
            .max { $0.date < $1.date }
        guard let latest, let metrics = latest.metrics else { return nil }
        return (metrics, latest.date)
    }

    /// Weight change vs. roughly a week earlier, using the nearest weigh-ins.
    func weeklyDelta(for date: Date) -> Double? {
        guard let current = recentMetrics(asOf: date)?.metrics.weightLbs else { return nil }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: date) ?? date
        guard let prior = recentMetrics(asOf: weekAgo)?.metrics.weightLbs,
              prior != current else { return nil }
        return current - prior
    }

    /// Sticky defaults: last completed workout → template baseline.
    func stickyWorkout(for date: Date) -> WorkoutEntry {
        let day = Calendar.current.startOfDay(for: date)
        let last = logsByDay.values
            .filter { $0.date < day }
            .sorted { $0.date > $1.date }
            .compactMap(\.workout)
            .first { $0.status == .done || $0.status == .partial }
        if let last {
            var draft = last
            draft.status = .skipped   // not logged yet today
            draft.startedAt = nil
            return draft
        }
        let template = templates.first ?? .builtinPushA
        return WorkoutEntry(
            status: .skipped, template: template.key, title: template.title,
            exercises: template.exercises
        )
    }

    // MARK: - Trends (series extraction for the Visualize tab)

    private var sortedLogs: [DailyLog] {
        logsByDay.values.sorted { $0.date < $1.date }
    }

    /// Time series of a body metric across all logged days.
    func metricSeries(_ metric: BodyMetricKind) -> [MetricPoint] {
        sortedLogs.compactMap { log in
            guard let m = log.metrics else { return nil }
            let value: Double?
            switch metric {
            case .weight: value = m.weightLbs
            case .bodyFat: value = m.bodyFatPct
            case .bmi: value = m.bmi
            case .leanMass: value = m.leanMassLbs
            }
            return value.map { MetricPoint(date: log.date, value: $0) }
        }
    }

    /// Exercise names that have weighted sets, most-logged first — for the
    /// strength-progression picker.
    func loggedLiftNames() -> [String] {
        var counts: [String: Int] = [:]
        for log in sortedLogs {
            for exercise in log.workout?.exercises ?? [] where exercise.sets?.isEmpty == false {
                counts[exercise.name, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    /// Top-set weight for a given lift over time (heaviest set each session).
    func strengthSeries(lift: String) -> [MetricPoint] {
        sortedLogs.compactMap { log in
            guard let exercise = log.workout?.exercises.first(where: { $0.name == lift }),
                  let sets = exercise.sets, !sets.isEmpty else { return nil }
            let top = sets.map(\.weightLbs).max() ?? 0
            return MetricPoint(date: log.date, value: top)
        }
    }

    /// Weigh-ins split into fat-free (lean) + fat mass, oldest → newest.
    /// Uses lean mass when present (fat = weight − lean), else derives both
    /// from body-fat %. Skips weigh-ins with neither.
    func compositionSeries() -> [CompositionPoint] {
        sortedLogs.compactMap { log in
            guard let m = log.metrics else { return nil }
            let weight = m.weightLbs
            var lean = m.leanMassLbs
            var fat: Double?
            if let lean { fat = Swift.max(weight - lean, 0) }
            else if let bf = m.bodyFatPct {
                let f = weight * bf / 100
                fat = f
                lean = weight - f
            }
            guard let fatValue = fat, let leanValue = lean else { return nil }
            let bf = m.bodyFatPct ?? (weight > 0 ? fatValue / weight * 100 : 0)
            return CompositionPoint(
                date: log.date,
                leanLbs: (leanValue * 10).rounded() / 10,
                fatLbs: (fatValue * 10).rounded() / 10,
                bodyFatPct: (bf * 10).rounded() / 10
            )
        }
    }

    /// Trained-days count per ISO week, oldest → newest.
    func weeklyTrainingCounts(weeks: Int) -> [WeekBar] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var bars: [WeekBar] = []
        for offset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let dayInWeek = cal.date(byAdding: .weekOfYear, value: -offset, to: today),
                  let interval = cal.dateInterval(of: .weekOfYear, for: dayInWeek) else { continue }
            let count = logsByDay.values.filter {
                interval.contains($0.date) && ($0.workout?.status == .done || $0.workout?.status == .partial)
            }.count
            bars.append(WeekBar(weekStart: interval.start, count: count))
        }
        return bars
    }

    // MARK: - Writes (file-first, then cache)

    func upsert(_ log: DailyLog) {
        var toSave = log
        if toSave.createdAt == nil { toSave.createdAt = Date() }
        do {
            try vault.writeDailyLog(toSave)
            logsByDay[Calendar.current.startOfDay(for: toSave.date)] = toSave
            lastError = nil
        } catch {
            lastError = "Couldn't save to vault: \(error.localizedDescription)"
        }
    }

    private func editableLog(for date: Date) -> DailyLog {
        log(for: date) ?? DailyLog(date: Calendar.current.startOfDay(for: date))
    }

    func saveWorkout(_ workout: WorkoutEntry, on date: Date) {
        var log = editableLog(for: date)
        log.workout = workout
        upsert(log)
    }

    func addFood(_ entry: FoodEntry, on date: Date) {
        var log = editableLog(for: date)
        log.food.append(entry)
        log.food.sort { $0.at < $1.at }
        upsert(log)
    }

    func addPhoto(_ jpeg: Data, pose: PicPose, on date: Date) {
        do {
            let path = try vault.savePhoto(jpeg, date: date, pose: pose)
            var log = editableLog(for: date)
            log.pics.append(ProgressPic(path: path, pose: pose))
            upsert(log)
        } catch {
            lastError = "Couldn't save photo: \(error.localizedDescription)"
        }
    }

    /// Whether a Health sync is running (drives the Settings status line).
    private(set) var syncing = false

    /// Pulls HealthKit into the vault: every recent weigh-in lands in its own
    /// day's log; activity fills today plus any recent day that already has a
    /// log. Idempotent and change-gated, so re-running writes nothing new.
    func syncHealth(around date: Date) async {
        guard vaultConfigured, HealthKitService.isAvailable else { return }
        syncing = true
        defer { syncing = false }

        // Full weigh-in history — the whole body-composition record.
        for (day, metrics) in await HealthKitService.weighIns(since: .distantPast) {
            var log = editableLog(for: day)
            if log.metrics != metrics {
                log.metrics = metrics
                upsert(log)
            }
        }

        let today = Calendar.current.startOfDay(for: .now)
        var activityDays: Set<Date> = [today, Calendar.current.startOfDay(for: date)]
        for offset in 1...7 {
            if let d = Calendar.current.date(byAdding: .day, value: -offset, to: today),
               logsByDay[d] != nil {
                activityDays.insert(d)
            }
        }
        for day in activityDays {
            // Don't create an empty file for a past day that has no log.
            if day != today && logsByDay[day] == nil { continue }
            guard let activity = await HealthKitService.activity(for: day) else { continue }
            var log = editableLog(for: day)
            if log.activity?.moveKcal != activity.moveKcal
                || log.activity?.exerciseMin != activity.exerciseMin
                || log.activity?.standHours != activity.standHours
                || log.activity?.steps != activity.steps {
                log.activity = activity
                upsert(log)
            }
        }
    }
}

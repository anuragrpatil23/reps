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

    // Telemetry lives in CSVs, not the daily markdown. These are the in-memory
    // mirrors we flush whole-file on change; logsByDay is the joined view.
    private var metricsByDay: [Date: BodyMetrics] = [:]
    private var activityByDay: [Date: ActivitySummary] = [:]

    var vaultConfigured: Bool { vault.isConfigured }

    // MARK: - Load / rebuild

    func load() {
        // Daily markdown = workout/food/pics/note (plus legacy metrics/activity
        // in older files, which we honor until the next sync migrates them).
        var docs: [Date: DailyLog] = [:]
        for date in vault.listLogDates() {
            if let log = vault.readDailyLog(for: date) {
                docs[Calendar.current.startOfDay(for: date)] = log
            }
        }
        // CSV telemetry wins over any legacy markdown copy.
        metricsByDay = vault.readBodyComposition()
        activityByDay = vault.readActivity()
        for (day, log) in docs {
            if metricsByDay[day] == nil, let m = log.metrics { metricsByDay[day] = m }
            if activityByDay[day] == nil, let a = log.activity { activityByDay[day] = a }
        }

        // Join into the view model.
        logsByDay = [:]
        let allDays = Set(docs.keys).union(metricsByDay.keys).union(activityByDay.keys)
        for day in allDays {
            var log = docs[day] ?? DailyLog(date: day)
            log.metrics = metricsByDay[day]
            log.activity = activityByDay[day]
            logsByDay[day] = log
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

    // MARK: - Writes

    /// Persists the day's markdown doc (workout/food/pics/note) and refreshes
    /// the joined view. Telemetry is never written here — see flushTelemetry.
    private func writeDoc(_ log: DailyLog) {
        var toSave = log
        if toSave.createdAt == nil { toSave.createdAt = Date() }
        do {
            try vault.writeDailyLog(toSave)
            let day = Calendar.current.startOfDay(for: toSave.date)
            toSave.metrics = metricsByDay[day]     // keep the joined view whole
            toSave.activity = activityByDay[day]
            logsByDay[day] = toSave
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
        writeDoc(log)
    }

    /// Writes the free-prose journal to the day file's markdown body.
    func saveNote(_ note: String?, on date: Date) {
        var log = editableLog(for: date)
        log.note = note
        writeDoc(log)
    }

    func addFood(_ entry: FoodEntry, on date: Date) {
        var log = editableLog(for: date)
        log.food.append(entry)
        log.food.sort { $0.at < $1.at }
        writeDoc(log)
    }

    func addPhoto(_ jpeg: Data, pose: PicPose, on date: Date) {
        do {
            let path = try vault.savePhoto(jpeg, date: date, pose: pose)
            var log = editableLog(for: date)
            log.pics.append(ProgressPic(path: path, pose: pose))
            writeDoc(log)
        } catch {
            lastError = "Couldn't save photo: \(error.localizedDescription)"
        }
    }

    // MARK: - Telemetry sync (HealthKit → CSV)

    /// Whether a Health sync is running (drives the Settings status line).
    private(set) var syncing = false

    /// Pulls HealthKit into the telemetry CSVs: full weigh-in history →
    /// body-composition.csv, ~2 years of daily activity → activity.csv. Both
    /// are whole-file flushes, idempotent, and never touch the daily markdown.
    func syncHealth(around date: Date) async {
        guard vaultConfigured, HealthKitService.isAvailable else { return }
        syncing = true
        defer { syncing = false }

        let weighIns = await HealthKitService.weighIns(since: .distantPast)
        var metricsChanged = false
        for (day, metrics) in weighIns where metricsByDay[day] != metrics {
            metricsByDay[day] = metrics
            metricsChanged = true
        }

        let activity = await HealthKitService.activityHistory(days: 730)
        var activityChanged = false
        for (day, summary) in activity where activityByDay[day] != summary {
            activityByDay[day] = summary
            activityChanged = true
        }

        do {
            if metricsChanged { try vault.writeBodyComposition(metricsByDay) }
            if activityChanged { try vault.writeActivity(activityByDay) }
        } catch {
            lastError = "Couldn't save telemetry: \(error.localizedDescription)"
        }

        if metricsChanged || activityChanged { rejoin() }
    }

    /// Rebuild the joined view after telemetry changes (no file reads).
    private func rejoin() {
        let allDays = Set(logsByDay.keys).union(metricsByDay.keys).union(activityByDay.keys)
        for day in allDays {
            var log = logsByDay[day] ?? DailyLog(date: day)
            log.metrics = metricsByDay[day]
            log.activity = activityByDay[day]
            logsByDay[day] = log
        }
    }

    // MARK: - Cleanup (one-time migration of pre-split daily files)

    /// Result of the last cleanup run, for the Settings status line.
    var cleanupSummary: String?

    /// Migrate legacy daily markdown: telemetry is flushed to the CSVs first
    /// (no data loss), then every `.md` is either rewritten without its
    /// metrics/activity frontmatter (if it has workout/food/pics/note) or
    /// deleted (if it held only telemetry). Explicit, never automatic.
    func cleanupDailyDocs() {
        guard vaultConfigured else { return }
        do {
            try vault.writeBodyComposition(metricsByDay)
            try vault.writeActivity(activityByDay)
        } catch {
            lastError = "Couldn't write telemetry before cleanup: \(error.localizedDescription)"
            return
        }

        var deleted = 0
        var rewritten = 0
        for day in vault.listLogDates().map({ Calendar.current.startOfDay(for: $0) }) {
            let log = logsByDay[day] ?? DailyLog(date: day)
            let hasJournal = log.workout != nil || !log.food.isEmpty
                || !log.pics.isEmpty || (log.note?.isEmpty == false)
            do {
                if hasJournal {
                    writeDoc(log)                 // rewrites without telemetry keys
                    rewritten += 1
                } else {
                    try vault.deleteLog(for: day) // data is safe in the CSVs
                    var joined = DailyLog(date: day)
                    joined.metrics = metricsByDay[day]
                    joined.activity = activityByDay[day]
                    logsByDay[day] = joined
                    deleted += 1
                }
            } catch {
                lastError = "Cleanup failed on \(DailyLogCodec.dayString(day)): \(error.localizedDescription)"
            }
        }
        cleanupSummary = "Removed \(deleted) telemetry-only files, kept \(rewritten) notes."
    }

    // MARK: - Activity series (for the Trends Apple Health charts)

    func activitySeries(_ kind: ActivityKind) -> [MetricPoint] {
        activityByDay.keys.sorted().compactMap { day in
            guard let a = activityByDay[day] else { return nil }
            let value: Double?
            switch kind {
            case .steps: value = a.steps.map(Double.init)
            case .activeEnergy: value = a.moveKcal > 0 ? Double(a.moveKcal) : nil
            case .exercise: value = a.exerciseMin > 0 ? Double(a.exerciseMin) : nil
            case .restingHR: value = a.restingHR.map(Double.init)
            }
            return value.map { MetricPoint(date: day, value: $0) }
        }
    }
}

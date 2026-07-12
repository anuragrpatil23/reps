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
    private(set) var programs: [Program] = []
    private(set) var mealPlans: [MealPlan] = []
    private(set) var foods: [Food] = []
    private(set) var loaded = false
    var lastError: String?

    /// Key of the active training program (drives the day's scheduled workout).
    /// Persisted in UserDefaults — a preference, not vault data.
    private static let activeProgramDefaultsKey = "reps.activeProgramKey"
    var activeProgramKey: String? = UserDefaults.standard.string(forKey: activeProgramDefaultsKey) {
        didSet { UserDefaults.standard.set(activeProgramKey, forKey: Self.activeProgramDefaultsKey) }
    }
    var activeProgram: Program? {
        guard let key = activeProgramKey else { return nil }
        return programs.first { $0.key == key }
    }

    /// Key of the active meal plan (pre-fills each day's staples). Like the
    /// program key, it's a UserDefaults preference, not vault data.
    private static let activeMealPlanDefaultsKey = "reps.activeMealPlanKey"
    var activeMealPlanKey: String? = UserDefaults.standard.string(forKey: activeMealPlanDefaultsKey) {
        didSet { UserDefaults.standard.set(activeMealPlanKey, forKey: Self.activeMealPlanDefaultsKey) }
    }
    var activeMealPlan: MealPlan? {
        guard let key = activeMealPlanKey else { return nil }
        return mealPlans.first { $0.key == key }
    }

    /// Memoized food lookup — rebuilt only when `foods` changes, so it's not
    /// re-derived on every view render (kept the keyboard/UI responsive).
    private var foodsById: [String: Food] = [:]

    // Telemetry lives in CSVs, not the daily markdown. These are the in-memory
    // mirrors we flush whole-file on change; logsByDay is the joined view.
    private var metricsByDay: [Date: BodyMetrics] = [:]
    private var activityByDay: [Date: ActivitySummary] = [:]
    // Curated Apple Health series (heart.csv / respiratory.csv / sleep.csv) and workouts.
    private var heartByDay: [Date: [String: Double]] = [:]
    private var respiratoryByDay: [Date: [String: Double]] = [:]
    private var sleepByDay: [Date: [String: Double]] = [:]
    private(set) var workouts: [WorkoutRecord] = []

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
        heartByDay = vault.readHealth(HealthCsv.heartPath, columns: HealthCsv.heartColumns)
        respiratoryByDay = vault.readHealth(HealthCsv.respiratoryPath, columns: HealthCsv.respiratoryColumns)
        sleepByDay = vault.readHealth(HealthCsv.sleepPath, columns: HealthCsv.sleepColumns)
        workouts = vault.readWorkouts()
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
        programs = vault.readPrograms()
        mealPlans = vault.readMealPlans()
        foods = vault.readFoods()
        rebuildFoodIndex()
        loaded = true
    }

    // MARK: - Food database

    func food(_ id: String) -> Food? { foodsById[id] }

    private func rebuildFoodIndex() {
        foodsById = Dictionary(foods.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func saveFood(_ food: Food) {
        var updated = food
        updated.updatedAt = Date()
        if let index = foods.firstIndex(where: { $0.id == updated.id }) {
            foods[index] = updated
        } else {
            foods.append(updated)
        }
        rebuildFoodIndex()
        flushFoods()
    }

    func deleteFood(_ id: String) {
        foods.removeAll { $0.id == id }
        rebuildFoodIndex()
        flushFoods()
    }

    private func flushFoods() {
        do { try vault.writeFoods(foods) }
        catch { lastError = "Couldn't save food: \(error.localizedDescription)" }
    }

    /// A unique slug id for a new food name (suffixes on collision).
    func uniqueFoodId(for name: String) -> String {
        uniqueKey(for: name) { key in foodsById[key] != nil }
    }

    /// A unique key from a name, suffixing while `taken` reports a collision.
    private func uniqueKey(for name: String, taken: (String) -> Bool) -> String {
        let base = Food.slug(for: name)
        guard taken(base) else { return base }
        var n = 2
        while taken("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    // MARK: - Templates (workout definitions)

    func template(_ key: String) -> WorkoutTemplate? {
        templates.first { $0.key == key }
    }

    func uniqueTemplateKey(for title: String) -> String {
        uniqueKey(for: title) { key in templates.contains { $0.key == key } }
    }

    func saveTemplate(_ template: WorkoutTemplate) {
        if let index = templates.firstIndex(where: { $0.key == template.key }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
        do { try vault.writeTemplate(template) }
        catch { lastError = "Couldn't save workout: \(error.localizedDescription)" }
    }

    func deleteTemplate(_ key: String) {
        templates.removeAll { $0.key == key }
        // Drop the deleted template from any program rotation that referenced it.
        for index in programs.indices where programs[index].rotation.contains(key) {
            programs[index].rotation.removeAll { $0 == key }
            try? vault.writeProgram(programs[index])
        }
        do { try vault.deleteTemplate(key: key) }
        catch { lastError = "Couldn't delete workout: \(error.localizedDescription)" }
    }

    // MARK: - Programs (training blocks)

    func uniqueProgramKey(for title: String) -> String {
        uniqueKey(for: title) { key in programs.contains { $0.key == key } }
    }

    func saveProgram(_ program: Program) {
        if let index = programs.firstIndex(where: { $0.key == program.key }) {
            programs[index] = program
        } else {
            programs.append(program)
        }
        if activeProgramKey == nil { activeProgramKey = program.key }
        do { try vault.writeProgram(program) }
        catch { lastError = "Couldn't save program: \(error.localizedDescription)" }
    }

    func deleteProgram(_ key: String) {
        programs.removeAll { $0.key == key }
        if activeProgramKey == key { activeProgramKey = programs.first?.key }
        do { try vault.deleteProgram(key: key) }
        catch { lastError = "Couldn't delete program: \(error.localizedDescription)" }
    }

    /// Whether the active program schedules `date` as a rest day.
    func isScheduledRestDay(_ date: Date) -> Bool {
        activeProgram?.isRestDay(date) ?? false
    }

    // MARK: - Meal plans (daily food staples)

    func uniqueMealPlanKey(for title: String) -> String {
        uniqueKey(for: title) { key in mealPlans.contains { $0.key == key } }
    }

    func saveMealPlan(_ plan: MealPlan) {
        if let index = mealPlans.firstIndex(where: { $0.key == plan.key }) {
            mealPlans[index] = plan
        } else {
            mealPlans.append(plan)
        }
        if activeMealPlanKey == nil { activeMealPlanKey = plan.key }
        do { try vault.writeMealPlan(plan) }
        catch { lastError = "Couldn't save meal plan: \(error.localizedDescription)" }
    }

    func deleteMealPlan(_ key: String) {
        mealPlans.removeAll { $0.key == key }
        if activeMealPlanKey == key { activeMealPlanKey = mealPlans.first?.key }
        do { try vault.deleteMealPlan(key: key) }
        catch { lastError = "Couldn't delete meal plan: \(error.localizedDescription)" }
    }

    /// The active plan's staples not yet logged on `date`. A staple is "already
    /// logged" when a matching food_id (or free text, for text-only staples) is
    /// present in the day — so it drops off the planned list once you add it.
    func plannedStaples(for date: Date) -> [FoodEntry] {
        guard let plan = activeMealPlan else { return [] }
        let logged = log(for: date)?.food ?? []
        return plan.staples.filter { staple in
            !logged.contains { existing in
                if let id = staple.foodId { return existing.foodId == id }
                return existing.text == staple.text
            }
        }
    }

    /// Log every not-yet-logged staple from the active plan onto `date` at once.
    func logStaples(on date: Date) {
        let staples = plannedStaples(for: date)
        guard !staples.isEmpty else { return }
        var log = editableLog(for: date)
        log.food.append(contentsOf: staples)
        log.food.sort { $0.at < $1.at }
        writeDoc(log)
    }

    // MARK: - Apple Watch sessions (workouts.csv, per day)

    /// Recorded Apple Watch workout sessions on `date` (functional strength,
    /// walks, etc.), most recent first.
    func workoutSessions(on date: Date) -> [WorkoutRecord] {
        let day = Calendar.current.startOfDay(for: date)
        return workouts.filter { $0.day == day }.sorted { $0.start > $1.start }
    }

    /// Minutes of strength vs. other movement on a day — drives the Spine's
    /// stacked bar. Strength comes from recorded strength workouts (or a saved
    /// strength log when the watch didn't record one); walking/cardio comes from
    /// other recorded sessions, falling back to Apple's exercise minutes on days
    /// with no discrete workout at all (a ring closed by casual movement).
    func trainingSplit(on date: Date) -> (strength: Double, walk: Double) {
        let sessions = workoutSessions(on: date)
        let isStrength: (WorkoutRecord) -> Bool = { $0.type.lowercased().contains("strength") }
        var strength = sessions.filter(isStrength).reduce(0) { $0 + $1.durationMin }
        let walkSessions = sessions.filter { !isStrength($0) }.reduce(0) { $0 + $1.durationMin }

        let day = log(for: date)
        if strength == 0, let w = day?.workout, w.status == .done || w.status == .partial {
            strength = Double(w.durationMin ?? 45)
        }
        var walk = walkSessions
        if sessions.isEmpty && strength == 0 {
            walk = Double(day?.activity?.exerciseMin ?? 0)
        }
        return (strength, walk)
    }

    /// The night's sleep for `date` (keyed to the wake-up day): asleep/in-bed
    /// totals and per-stage minutes (rem/core/deep/awake), as recorded by the
    /// watch. Nil when there's no sleep sample for that day.
    func sleep(on date: Date) -> [String: Double]? {
        sleepByDay[Calendar.current.startOfDay(for: date)]
    }

    // MARK: - Macros

    /// Macros for a single logged entry (food × servings), if it references one.
    func macros(for entry: FoodEntry) -> Macros? {
        guard let id = entry.foodId, let food = foodsById[id] else { return nil }
        return food.macros.scaled(by: entry.servings ?? 1)
    }

    /// Total macros logged on a day.
    func macros(for date: Date) -> Macros {
        (log(for: date)?.food ?? []).reduce(Macros()) { total, entry in
            total + (macros(for: entry) ?? Macros())
        }
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

    /// Sticky defaults for the day, program-aware:
    /// - active program schedules a rest day → a rest entry.
    /// - active program schedules a template → that template, with weights
    ///   carried from its last completed session (falls back to the baseline).
    /// - no active program → last completed workout → first template baseline.
    func stickyWorkout(for date: Date) -> WorkoutEntry {
        let day = Calendar.current.startOfDay(for: date)

        if let program = activeProgram {
            if program.isRestDay(date) {
                return WorkoutEntry(status: .rest)
            }
            if let key = program.scheduledTemplateKey(on: date),
               let template = template(key) {
                let lastSets = logsByDay.values
                    .filter { $0.date < day }
                    .sorted { $0.date > $1.date }
                    .compactMap(\.workout)
                    .first { ($0.status == .done || $0.status == .partial) && $0.template == key }
                return WorkoutEntry(
                    status: .skipped, template: template.key, title: template.title,
                    exercises: lastSets?.exercises ?? template.exercises
                )
            }
        }

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

    /// Remove a logged food entry from a day (an explicit user edit, allowed by
    /// contract §5). No-op if the day or entry is gone.
    func removeFood(_ entry: FoodEntry, on date: Date) {
        guard var log = log(for: date) else { return }
        log.food.removeAll { $0.id == entry.id }
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

        // Curated vitals / sleep / workouts — full history into their CSVs.
        let days = HealthKitService.fullHistoryDays
        let heart = await HealthKitService.heartDaily(days: days)
        let respiratory = await HealthKitService.respiratoryDaily(days: days)
        let sleep = await HealthKitService.sleepDaily(days: days)
        let gymWorkouts = await HealthKitService.workoutHistory(days: days)

        do {
            if metricsChanged { try vault.writeBodyComposition(metricsByDay) }
            if activityChanged { try vault.writeActivity(activityByDay) }
            if !heart.isEmpty {
                heartByDay = heart
                try vault.writeHealth(heart, columns: HealthCsv.heartColumns, to: HealthCsv.heartPath)
            }
            if !respiratory.isEmpty {
                respiratoryByDay = respiratory
                try vault.writeHealth(respiratory, columns: HealthCsv.respiratoryColumns, to: HealthCsv.respiratoryPath)
            }
            if !sleep.isEmpty {
                sleepByDay = sleep
                try vault.writeHealth(sleep, columns: HealthCsv.sleepColumns, to: HealthCsv.sleepPath)
            }
            if !gymWorkouts.isEmpty {
                workouts = gymWorkouts
                try vault.writeWorkouts(gymWorkouts)
            }
        } catch {
            lastError = "Couldn't save telemetry: \(error.localizedDescription)"
        }

        if metricsChanged || activityChanged { rejoin() }
    }

    /// A daily health column as a chart series (optionally scaled, e.g. min→hr).
    private func healthSeries(_ source: [Date: [String: Double]], _ column: String, scale: Double = 1) -> [MetricPoint] {
        source.keys.sorted().compactMap { day in
            source[day]?[column].map { MetricPoint(date: day, value: ($0 * scale * 10).rounded() / 10) }
        }
    }

    func heartSeries(_ column: String) -> [MetricPoint] { healthSeries(heartByDay, column) }
    func respiratorySeries(_ column: String) -> [MetricPoint] { healthSeries(respiratoryByDay, column) }
    /// Sleep asleep-time as hours.
    func sleepHoursSeries() -> [MetricPoint] { healthSeries(sleepByDay, "asleep_min", scale: 1.0 / 60.0) }

    /// Nightly sleep split into stages (hours), oldest → newest. Only nights the
    /// watch broke into stages (deep/core/REM) are included.
    func sleepStageSeries() -> [SleepNight] {
        sleepByDay.keys.sorted().compactMap { day in
            guard let s = sleepByDay[day] else { return nil }
            let deep = s["deep_min"] ?? 0, core = s["core_min"] ?? 0
            let rem = s["rem_min"] ?? 0, awake = s["awake_min"] ?? 0
            guard deep + core + rem > 0 else { return nil }   // needs stage data
            return SleepNight(date: day, deepH: deep / 60, coreH: core / 60,
                              remH: rem / 60, awakeH: awake / 60)
        }
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

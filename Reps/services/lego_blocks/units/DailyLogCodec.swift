import Foundation
import Yams

/// (De)serializes DailyLog / WorkoutTemplate to the markdown + YAML
/// frontmatter shapes defined in docs/DATA-CONTRACT.md (schema v1).
/// Key mapping is manual and explicit so the on-disk contract — snake_case,
/// units in key names, omit-don't-null — never drifts with Swift naming.
@MainActor
enum DailyLogCodec {
    static let schemaVersion = 1

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
    static func day(from string: String) -> Date? { dayFormatter.date(from: string) }

    // MARK: - Daily log → markdown

    static func markdown(for log: DailyLog) throws -> String {
        var fm: [String: Any] = [
            "schema_version": schemaVersion,
            "type": "sffit-daily-log",
            "date": dayString(log.date),
            "source": "reps-app",
            "created_at": isoFormatter.string(from: log.createdAt ?? Date()),
            "updated_at": isoFormatter.string(from: Date()),
        ]
        // NB: body metrics and activity are NOT written here — they live in the
        // telemetry CSVs (see TelemetryCsv / docs/DATA-CONTRACT.md). The daily
        // markdown holds only what you log/journal.
        if let w = log.workout {
            var d: [String: Any] = ["status": w.status.rawValue]
            if let v = w.template { d["template"] = v }
            if let v = w.title { d["title"] = v }
            if let v = w.startedAt { d["started_at"] = isoFormatter.string(from: v) }
            if let v = w.durationMin { d["duration_min"] = v }
            if !w.exercises.isEmpty { d["exercises"] = w.exercises.map(exerciseDict) }
            fm["workout"] = d
        }
        if !log.food.isEmpty {
            fm["food"] = log.food.map { entry -> [String: Any] in
                var d: [String: Any] = ["at": entry.at]
                if let v = entry.text { d["text"] = v }
                if let v = entry.recipe { d["recipe"] = v }
                if let v = entry.photo { d["photo"] = v }
                if let v = entry.foodId { d["food_id"] = v }
                if let v = entry.servings { d["servings"] = v }
                return d
            }
        }
        if !log.pics.isEmpty {
            fm["pics"] = log.pics.map { ["path": $0.path, "pose": $0.pose.rawValue] }
        }
        let yaml = try Yams.dump(object: fm, sortKeys: true)
        let body = log.note.map { "\n\($0)\n" } ?? ""
        return "---\n\(yaml)---\n\(body)"
    }

    private static func exerciseDict(_ e: ExerciseEntry) -> [String: Any] {
        var d: [String: Any] = ["name": e.name]
        if let sets = e.sets {
            d["sets"] = sets.map { ["reps": $0.reps, "weight_lbs": $0.weightLbs] }
        }
        if let v = e.durationMin { d["duration_min"] = v }
        if let v = e.inclinePct { d["incline_pct"] = v }
        if let v = e.speedMph { d["speed_mph"] = v }
        return d
    }

    // MARK: - Markdown → daily log

    static func parseDailyLog(_ text: String, date: Date) -> DailyLog? {
        guard let (fm, body) = splitFrontmatter(text) else { return nil }
        var log = DailyLog(date: date)
        log.createdAt = (fm["created_at"] as? String).flatMap(isoFormatter.date)
        if let m = fm["metrics"] as? [String: Any], let weight = asDouble(m["weight_lbs"]) {
            log.metrics = BodyMetrics(
                weightLbs: weight,
                bmi: asDouble(m["bmi"]),
                bodyFatPct: asDouble(m["body_fat_pct"]),
                leanMassLbs: asDouble(m["lean_mass_lbs"]),
                measuredAt: (m["measured_at"] as? String).flatMap(isoFormatter.date)
            )
        }
        if let a = fm["activity"] as? [String: Any] {
            log.activity = ActivitySummary(
                moveKcal: asInt(a["move_kcal"]) ?? 0,
                moveGoalKcal: asInt(a["move_goal_kcal"]) ?? 500,
                exerciseMin: asInt(a["exercise_min"]) ?? 0,
                exerciseGoalMin: asInt(a["exercise_goal_min"]) ?? 30,
                standHours: asInt(a["stand_hours"]) ?? 0,
                standGoalHours: asInt(a["stand_goal_hours"]) ?? 12,
                steps: asInt(a["steps"])
            )
        }
        if let w = fm["workout"] as? [String: Any],
           let status = (w["status"] as? String).flatMap(WorkoutStatus.init(rawValue:)) {
            log.workout = WorkoutEntry(
                status: status,
                template: w["template"] as? String,
                title: w["title"] as? String,
                startedAt: (w["started_at"] as? String).flatMap(isoFormatter.date),
                durationMin: asInt(w["duration_min"]),
                exercises: parseExercises(w["exercises"])
            )
        }
        if let food = fm["food"] as? [[String: Any]] {
            log.food = food.compactMap { d in
                guard let at = d["at"] as? String else { return nil }
                return FoodEntry(at: at, text: d["text"] as? String,
                                 recipe: d["recipe"] as? String, photo: d["photo"] as? String,
                                 foodId: d["food_id"] as? String, servings: asDouble(d["servings"]))
            }
        }
        if let pics = fm["pics"] as? [[String: Any]] {
            log.pics = pics.compactMap { d in
                guard let path = d["path"] as? String else { return nil }
                let pose = (d["pose"] as? String).flatMap(PicPose.init(rawValue:)) ?? .other
                return ProgressPic(path: path, pose: pose)
            }
        }
        let note = body.trimmingCharacters(in: .whitespacesAndNewlines)
        log.note = note.isEmpty ? nil : note
        return log
    }

    // MARK: - Templates

    /// A workout template → markdown (the app owns `sffit/templates/`, so it can
    /// now write these, not just read seeds).
    static func templateMarkdown(for template: WorkoutTemplate) throws -> String {
        let fm: [String: Any] = [
            "schema_version": schemaVersion,
            "type": "sffit-workout-template",
            "key": template.key,
            "title": template.title,
            "exercises": template.exercises.map(exerciseDict),
        ]
        let yaml = try Yams.dump(object: fm, sortKeys: true)
        return "---\n\(yaml)---\n"
    }

    static func parseTemplate(_ text: String) -> WorkoutTemplate? {
        guard let (fm, _) = splitFrontmatter(text),
              fm["type"] as? String == "sffit-workout-template",
              let key = fm["key"] as? String else { return nil }
        return WorkoutTemplate(
            key: key,
            title: fm["title"] as? String ?? key,
            exercises: parseExercises(fm["exercises"])
        )
    }

    // MARK: - Programs (training blocks)

    static func programMarkdown(for program: Program) throws -> String {
        let fm: [String: Any] = [
            "schema_version": schemaVersion,
            "type": "sffit-program",
            "key": program.key,
            "title": program.title,
            "phase": program.phase.rawValue,
            "rotation": program.rotation,
            "rest_days": program.restDays.sorted().map(\.code),
            "anchor": dayString(program.anchor),
        ]
        let yaml = try Yams.dump(object: fm, sortKeys: true)
        return "---\n\(yaml)---\n"
    }

    static func parseProgram(_ text: String) -> Program? {
        guard let (fm, _) = splitFrontmatter(text),
              fm["type"] as? String == "sffit-program",
              let key = fm["key"] as? String else { return nil }
        let rotation = (fm["rotation"] as? [Any])?.compactMap { $0 as? String } ?? []
        let restCodes = (fm["rest_days"] as? [Any])?.compactMap { $0 as? String } ?? []
        let restDays = Set(restCodes.compactMap(Weekday.from(code:)))
        let anchor = (fm["anchor"] as? String).flatMap(day(from:)) ?? Date()
        let phase = (fm["phase"] as? String).flatMap(TrainingPhase.init(rawValue:)) ?? .other
        return Program(
            key: key,
            title: fm["title"] as? String ?? key,
            phase: phase,
            rotation: rotation,
            restDays: restDays,
            anchor: anchor
        )
    }

    // MARK: - Meal plans (daily food staples)

    static func mealPlanMarkdown(for plan: MealPlan) throws -> String {
        let fm: [String: Any] = [
            "schema_version": schemaVersion,
            "type": "sffit-meal-plan",
            "key": plan.key,
            "title": plan.title,
            "phase": plan.phase.rawValue,
            "staples": plan.staples.map(encodeFood),
        ]
        let yaml = try Yams.dump(object: fm, sortKeys: true)
        return "---\n\(yaml)---\n"
    }

    static func parseMealPlan(_ text: String) -> MealPlan? {
        guard let (fm, _) = splitFrontmatter(text),
              fm["type"] as? String == "sffit-meal-plan",
              let key = fm["key"] as? String else { return nil }
        let staples = (fm["staples"] as? [[String: Any]])?.compactMap(decodeFood) ?? []
        let phase = (fm["phase"] as? String).flatMap(TrainingPhase.init(rawValue:)) ?? .other
        return MealPlan(key: key, title: fm["title"] as? String ?? key, phase: phase, staples: staples)
    }

    /// One food entry ⇄ YAML dict — shared by day logs and meal-plan staples.
    static func encodeFood(_ entry: FoodEntry) -> [String: Any] {
        var d: [String: Any] = ["at": entry.at]
        if let v = entry.text { d["text"] = v }
        if let v = entry.recipe { d["recipe"] = v }
        if let v = entry.photo { d["photo"] = v }
        if let v = entry.foodId { d["food_id"] = v }
        if let v = entry.servings { d["servings"] = v }
        return d
    }

    static func decodeFood(_ d: [String: Any]) -> FoodEntry? {
        let at = d["at"] as? String ?? ""
        return FoodEntry(at: at, text: d["text"] as? String, recipe: d["recipe"] as? String,
                         photo: d["photo"] as? String, foodId: d["food_id"] as? String,
                         servings: asDouble(d["servings"]))
    }

    // MARK: - Shared plumbing

    private static func parseExercises(_ raw: Any?) -> [ExerciseEntry] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard let name = d["name"] as? String else { return nil }
            var sets: [SetEntry]?
            if let rawSets = d["sets"] as? [[String: Any]] {
                sets = rawSets.compactMap { s in
                    guard let reps = asInt(s["reps"]), let weight = asDouble(s["weight_lbs"]) else { return nil }
                    return SetEntry(reps: reps, weightLbs: weight)
                }
            }
            return ExerciseEntry(
                name: name, sets: sets,
                durationMin: asInt(d["duration_min"]),
                inclinePct: asDouble(d["incline_pct"]),
                speedMph: asDouble(d["speed_mph"])
            )
        }
    }

    private static func splitFrontmatter(_ text: String) -> ([String: Any], String)? {
        guard text.hasPrefix("---") else { return nil }
        let afterOpen = text.index(text.startIndex, offsetBy: 3)
        guard let close = text.range(of: "\n---", range: afterOpen..<text.endIndex) else { return nil }
        let yaml = String(text[afterOpen..<close.lowerBound])
        let body = String(text[close.upperBound...]).drop { $0 == "-" }
        guard let fm = (try? Yams.load(yaml: yaml)) as? [String: Any] else { return nil }
        return (fm, String(body))
    }

    private static func asDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    private static func asInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        return nil
    }
}

import Foundation

/// CSV codec for the two telemetry files that hold machine-generated,
/// append-only time series (see docs/DATA-CONTRACT.md):
///   sffit/data/body-composition.csv  — weigh-ins (FitDays → Health)
///   sffit/data/activity.csv          — daily Apple Watch / Activity
/// Keeping these out of the per-day markdown keeps the YAML lean and makes the
/// whole history one grep-able, importable file each.
@MainActor
enum TelemetryCsv {
    static let bodyCompositionPath = "sffit/data/body-composition.csv"
    static let activityPath = "sffit/data/activity.csv"

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

    // MARK: - Body composition

    private static let bodyHeader = "date,weight_lbs,bmi,body_fat_pct,lean_mass_lbs,measured_at"

    static func parseBodyComposition(_ text: String) -> [Date: BodyMetrics] {
        var result: [Date: BodyMetrics] = [:]
        for row in rows(text, expectedHeaderPrefix: "date,weight_lbs") {
            guard let day = dayFormatter.date(from: row[0]),
                  let weight = dbl(row, 1) else { continue }
            result[day] = BodyMetrics(
                weightLbs: weight,
                bmi: dbl(row, 2),
                bodyFatPct: dbl(row, 3),
                leanMassLbs: dbl(row, 4),
                measuredAt: str(row, 5).flatMap(isoFormatter.date)
            )
        }
        return result
    }

    static func formatBodyComposition(_ metrics: [Date: BodyMetrics]) -> String {
        var lines = [bodyHeader]
        for day in metrics.keys.sorted() {
            let m = metrics[day]!
            lines.append([
                dayFormatter.string(from: day),
                num(m.weightLbs),
                m.bmi.map(num) ?? "",
                m.bodyFatPct.map(num) ?? "",
                m.leanMassLbs.map(num) ?? "",
                m.measuredAt.map(isoFormatter.string) ?? "",
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Activity

    private static let activityHeader =
        "date,steps,resting_hr,move_kcal,move_goal_kcal,exercise_min,exercise_goal_min,stand_hours,stand_goal_hours"

    static func parseActivity(_ text: String) -> [Date: ActivitySummary] {
        var result: [Date: ActivitySummary] = [:]
        for row in rows(text, expectedHeaderPrefix: "date,steps") {
            guard let day = dayFormatter.date(from: row[0]) else { continue }
            result[day] = ActivitySummary(
                moveKcal: int(row, 3) ?? 0,
                moveGoalKcal: int(row, 4) ?? 500,
                exerciseMin: int(row, 5) ?? 0,
                exerciseGoalMin: int(row, 6) ?? 30,
                standHours: int(row, 7) ?? 0,
                standGoalHours: int(row, 8) ?? 12,
                steps: int(row, 1),
                restingHR: int(row, 2)
            )
        }
        return result
    }

    static func formatActivity(_ activity: [Date: ActivitySummary]) -> String {
        var lines = [activityHeader]
        for day in activity.keys.sorted() {
            let a = activity[day]!
            var cells: [String] = [dayFormatter.string(from: day)]
            cells.append(a.steps.map(String.init) ?? "")
            cells.append(a.restingHR.map(String.init) ?? "")
            cells.append(String(a.moveKcal))
            cells.append(String(a.moveGoalKcal))
            cells.append(String(a.exerciseMin))
            cells.append(String(a.exerciseGoalMin))
            cells.append(String(a.standHours))
            cells.append(String(a.standGoalHours))
            lines.append(cells.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Shared plumbing

    private static func rows(_ text: String, expectedHeaderPrefix: String) -> [[String]] {
        text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix(expectedHeaderPrefix) }
            .map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
    }

    private static func str(_ row: [String], _ i: Int) -> String? {
        guard row.indices.contains(i) else { return nil }
        let v = row[i].trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }
    private static func dbl(_ row: [String], _ i: Int) -> Double? { str(row, i).flatMap(Double.init) }
    private static func int(_ row: [String], _ i: Int) -> Int? { str(row, i).flatMap { Int(Double($0) ?? .nan) } }

    /// Trim trailing ".0" so whole numbers read cleanly.
    private static func num(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

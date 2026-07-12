import Foundation

/// CSV codecs for the curated Apple Health export (see docs/DATA-CONTRACT.md).
/// Most health files are the same shape — a date plus named numeric columns —
/// so one generic codec handles heart / respiratory / sleep. Workouts are
/// row-per-event with a string type, so they get their own codec.
@MainActor
enum HealthCsv {
    static let heartPath = "sffit/data/heart.csv"
    static let respiratoryPath = "sffit/data/respiratory.csv"
    static let sleepPath = "sffit/data/sleep.csv"
    static let workoutsPath = "sffit/data/workouts.csv"

    static let heartColumns = ["avg_hr", "min_hr", "max_hr", "walking_hr", "hrv_sdnn", "vo2max"]
    static let respiratoryColumns = ["spo2_avg", "spo2_min", "respiratory_rate", "wrist_temp_c"]
    static let sleepColumns = ["asleep_min", "in_bed_min", "rem_min", "core_min", "deep_min", "awake_min"]

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

    // MARK: - Generic daily-numeric (heart / respiratory / sleep)

    static func format(_ rows: [Date: [String: Double]], columns: [String]) -> String {
        var lines = ["date," + columns.joined(separator: ",")]
        for day in rows.keys.sorted() {
            let values = rows[day] ?? [:]
            var cells = [dayFormatter.string(from: day)]
            for column in columns {
                cells.append(values[column].map(num) ?? "")
            }
            lines.append(cells.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func parse(_ text: String, columns: [String]) -> [Date: [String: Double]] {
        var result: [Date: [String: Double]] = [:]
        for line in dataLines(text) {
            let cells = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard let first = cells.first, let day = dayFormatter.date(from: first) else { continue }
            var values: [String: Double] = [:]
            for (index, column) in columns.enumerated() {
                let cell = index + 1 < cells.count ? cells[index + 1] : ""
                if let v = Double(cell) { values[column] = v }
            }
            if !values.isEmpty { result[day] = values }
        }
        return result
    }

    // MARK: - Workouts (row per event)

    private static let workoutHeader = "start,type,duration_min,energy_kcal,distance_mi,avg_hr"

    static func formatWorkouts(_ workouts: [WorkoutRecord]) -> String {
        var lines = [workoutHeader]
        for w in workouts.sorted(by: { $0.start < $1.start }) {
            var cells = [isoFormatter.string(from: w.start), w.type, num(w.durationMin)]
            cells.append(w.energyKcal.map(num) ?? "")
            cells.append(w.distanceMi.map(num) ?? "")
            cells.append(w.avgHR.map(num) ?? "")
            lines.append(cells.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func parseWorkouts(_ text: String) -> [WorkoutRecord] {
        dataLines(text).compactMap { line in
            let c = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 3, let start = isoFormatter.date(from: c[0]),
                  let duration = Double(c[2]) else { return nil }
            return WorkoutRecord(
                start: start,
                type: c[1],
                durationMin: duration,
                energyKcal: c.count > 3 ? Double(c[3]) : nil,
                distanceMi: c.count > 4 ? Double(c[4]) : nil,
                avgHR: c.count > 5 ? Double(c[5]) : nil
            )
        }
    }

    // MARK: - Shared

    private static func dataLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix("date,") && !$0.hasPrefix("start,") }
    }

    private static func num(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String((value * 10).rounded() / 10)
    }
}

import Foundation

/// Deterministic sample data so the Today page and Spine render real-feeling
/// content before the vault store and HealthKit land. Numbers echo the actual
/// April 2026 cut logs (bench 95, lat pulldown 115, incline walks).
enum MockData {
    static let calendar = Calendar.current

    static func day(_ offset: Int, from anchor: Date = .now) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: -offset, to: anchor) ?? anchor)
    }

    static let pushA = WorkoutEntry(
        status: .done,
        template: "push-a",
        title: "Push A",
        startedAt: nil,
        durationMin: 55,
        exercises: [
            ExerciseEntry(name: "Bench press", sets: [
                SetEntry(reps: 8, weightLbs: 95),
                SetEntry(reps: 8, weightLbs: 95),
                SetEntry(reps: 6, weightLbs: 100),
            ]),
            ExerciseEntry(name: "Lat pulldown", sets: [
                SetEntry(reps: 10, weightLbs: 115),
                SetEntry(reps: 10, weightLbs: 115),
            ]),
            ExerciseEntry(name: "Bent-over row", sets: [
                SetEntry(reps: 8, weightLbs: 70),
                SetEntry(reps: 8, weightLbs: 70),
            ]),
            ExerciseEntry(name: "Incline walk", durationMin: 20, inclinePct: 12, speedMph: 3),
        ]
    )

    /// ~9 weeks of history: a believable train/log/miss texture for the Spine.
    static let logs: [DailyLog] = {
        // Repeating weekly pattern, most recent day first:
        // t = trained, l = logged only, e = empty
        let pattern: [Character] = Array("tlttelt tltteel tlttelt lltteet tlttelt tetteel tlttelt tltteet tlttelt".replacingOccurrences(of: " ", with: ""))
        return pattern.enumerated().map { offset, mark in
            let date = day(offset)
            var log = DailyLog(date: date)
            switch mark {
            case "t":
                log.workout = pushA
                log.metrics = BodyMetrics(weightLbs: 138.2 + Double(offset) * 0.045)
                log.activity = ActivitySummary(moveKcal: 520, exerciseMin: 42, standHours: 11, steps: 8934)
                log.food = [
                    FoodEntry(at: "08:30", text: "oats + Oikos + blueberries"),
                    FoodEntry(at: "13:00", text: "chicken + veggies + sourdough"),
                    FoodEntry(at: "19:30", text: "protein shake, cashews"),
                ]
            case "l":
                log.metrics = BodyMetrics(weightLbs: 138.4 + Double(offset) * 0.045)
                log.activity = ActivitySummary(moveKcal: 380, exerciseMin: 18, standHours: 9, steps: 6120)
                log.food = [FoodEntry(at: "09:00", text: "oats + Oikos")]
            default:
                break
            }
            return log
        }
    }()

    static func log(for date: Date) -> DailyLog? {
        logs.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Weight delta vs. 7 days prior, if both exist.
    static func weeklyDelta(for date: Date) -> Double? {
        guard let today = log(for: date)?.metrics?.weightLbs else { return nil }
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: date) ?? date
        guard let prior = log(for: weekAgo)?.metrics?.weightLbs else { return nil }
        return today - prior
    }
}

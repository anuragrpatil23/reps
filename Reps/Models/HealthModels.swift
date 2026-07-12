import Foundation

/// One completed workout (from HealthKit's HKWorkout). Stored one-per-row in
/// workouts.csv — not daily-aggregated, since a day can hold several.
struct WorkoutRecord: Identifiable, Sendable {
    let start: Date
    let type: String
    let durationMin: Double
    let energyKcal: Double?
    let distanceMi: Double?
    let avgHR: Double?

    var id: Date { start }
    var day: Date { Calendar.current.startOfDay(for: start) }
}

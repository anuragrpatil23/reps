import Foundation

/// Mirror of the `sffit-workout-template` schema in docs/DATA-CONTRACT.md.
struct WorkoutTemplate: Identifiable, Sendable {
    var key: String
    var title: String
    var exercises: [ExerciseEntry]

    var id: String { key }

    /// Fallback until template files exist in the vault — seeded from the
    /// April 2026 cut routine. Editing a logged workout never mutates this.
    static let builtinPushA = WorkoutTemplate(
        key: "push-a",
        title: "Push A",
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
}

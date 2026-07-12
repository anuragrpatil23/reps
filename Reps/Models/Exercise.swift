import Foundation

/// The user's sex — selected in Settings, drives per-exercise default weights.
/// Stored as a raw string in UserDefaults under "reps.sex".
enum Sex: String, CaseIterable, Sendable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    static var current: Sex {
        Sex(rawValue: UserDefaults.standard.string(forKey: "reps.sex") ?? "") ?? .male
    }
}

/// A how-to reference for an exercise — a labelled link (usually a YouTube form
/// video). Stored inline on the exercise in the library file.
struct ExerciseLink: Codable, Sendable, Equatable, Identifiable {
    var label: String
    var url: String

    var id: String { url + label }
}

/// One entry in the personal exercise library (sffit/exercises.md). Workout
/// templates and logged workouts reference an exercise by `key`, the way logged
/// meals reference a `Food` by id — so names stay consistent and each exercise
/// carries its form cue and how-to links wherever it appears.
struct Exercise: Identifiable, Sendable, Equatable {
    var key: String             // stable slug, referenced by templates/logs
    var name: String
    var muscle: String          // grouping: chest, back, legs, shoulders, arms, core, cardio…
    var cue: String?            // one-line form reminder
    var links: [ExerciseLink]   // how-to videos etc.
    var defaultReps: Int = 10               // starting reps for a fresh set
    var defaultWeightMale: Double = 0       // starting working weight, male (0 = bodyweight/unset)
    var defaultWeightFemale: Double = 0     // starting working weight, female

    var id: String { key }

    /// Starting weight for the selected sex.
    func defaultWeight(for sex: Sex) -> Double {
        switch sex {
        case .male: defaultWeightMale
        case .female: defaultWeightFemale
        }
    }

    /// A URL-safe slug from a name, for the key. Shares the food slugger.
    static func slug(for name: String) -> String { Food.slug(for: name) }

    /// The in-app default library. On first run this is written to the vault as
    /// `sffit/exercises.md` if that file doesn't exist yet (see `LogStore.load`);
    /// from then on the vault file is the source of truth. Keeping the default in
    /// code is deliberate: it's the zero-config seed AND the template the AI
    /// trainer works off — it writes/edits the same `exercises.md` the UI reads.
    ///
    /// Enough to build a push/pull/legs split out of the box. Links are left
    /// empty for you (or the trainer) to fill in. Starting weights are tuned for
    /// a lighter lifter (male ≈ 128 lb / 100 lb lean; female scaled lighter) and
    /// are just a starting point — edit them per exercise, and they follow the
    /// Sex selected in Settings.
    static let builtins: [Exercise] = [
        Exercise(key: "bench-press", name: "Bench press", muscle: "chest", cue: "Elbows ~45°, touch mid-chest", links: [], defaultWeightMale: 95, defaultWeightFemale: 55),
        Exercise(key: "incline-dumbbell-press", name: "Incline dumbbell press", muscle: "chest", cue: "Bench ~30°, controlled stretch", links: [], defaultWeightMale: 40, defaultWeightFemale: 20),
        Exercise(key: "overhead-press", name: "Overhead press", muscle: "shoulders", cue: "Brace, bar over mid-foot", links: [], defaultWeightMale: 55, defaultWeightFemale: 30),
        Exercise(key: "incline-smith-shoulder-press", name: "Incline Smith machine shoulder press", muscle: "shoulders", cue: "Bar to upper chest, ribs down", links: [], defaultWeightMale: 65, defaultWeightFemale: 35),
        Exercise(key: "lateral-raise", name: "Lateral raise", muscle: "shoulders", cue: "Lead with elbows, no swing", links: [], defaultWeightMale: 15, defaultWeightFemale: 8),
        Exercise(key: "lat-pulldown", name: "Lat pulldown", muscle: "back", cue: "Drive elbows down, chest up", links: [], defaultWeightMale: 115, defaultWeightFemale: 70),
        Exercise(key: "bent-over-row", name: "Bent-over row", muscle: "back", cue: "Flat back, pull to belly", links: [], defaultWeightMale: 70, defaultWeightFemale: 40),
        Exercise(key: "smith-bent-over-row", name: "Smith machine bent-over row", muscle: "back", cue: "Flat back, pull bar to waist", links: [], defaultWeightMale: 95, defaultWeightFemale: 55),
        Exercise(key: "pull-up", name: "Pull-up", muscle: "back", cue: "Full hang to chin over bar", links: []),
        Exercise(key: "back-squat", name: "Back squat", muscle: "legs", cue: "Knees track toes, hips back", links: [], defaultWeightMale: 115, defaultWeightFemale: 75),
        Exercise(key: "romanian-deadlift", name: "Romanian deadlift", muscle: "legs", cue: "Hinge, soft knees, bar close", links: [], defaultWeightMale: 95, defaultWeightFemale: 65),
        Exercise(key: "leg-press", name: "Leg press", muscle: "legs", cue: "Don't lock out or round lower back", links: [], defaultWeightMale: 180, defaultWeightFemale: 120),
        Exercise(key: "seated-leg-curl", name: "Seated leg curl", muscle: "legs", cue: "Control the negative, no hip lift", links: [], defaultWeightMale: 90, defaultWeightFemale: 55),
        Exercise(key: "leg-extension", name: "Leg extension", muscle: "legs", cue: "Pause at the top, don't swing", links: [], defaultWeightMale: 90, defaultWeightFemale: 55),
        Exercise(key: "smith-hip-thrust", name: "Smith machine hip thrust", muscle: "legs", cue: "Chin tucked, full hip lockout, ribs down", links: [], defaultWeightMale: 135, defaultWeightFemale: 90),
        Exercise(key: "bicep-curl", name: "Bicep curl", muscle: "arms", cue: "Elbows pinned, no swing", links: [], defaultWeightMale: 25, defaultWeightFemale: 12),
        Exercise(key: "tricep-pushdown", name: "Tricep pushdown", muscle: "arms", cue: "Elbows tight, full lockout", links: [], defaultWeightMale: 40, defaultWeightFemale: 25),
        Exercise(key: "plank", name: "Plank", muscle: "core", cue: "Glutes tight, ribs down", links: []),
        Exercise(key: "incline-walk", name: "Incline walk", muscle: "cardio", cue: nil, links: []),
    ]
}

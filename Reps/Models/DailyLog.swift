import Foundation

// Swift mirror of docs/DATA-CONTRACT.md schema v1.
// These types will gain YAML (de)serialization when the vault store lands;
// for now they back the UI and the local cache design.

struct DailyLog: Identifiable, Codable, Sendable {
    var date: Date
    var createdAt: Date?
    var metrics: BodyMetrics?
    var activity: ActivitySummary?
    var workout: WorkoutEntry?
    var food: [FoodEntry] = []
    var pics: [ProgressPic] = []
    var note: String?

    var id: Date { date }
}

struct BodyMetrics: Codable, Sendable, Equatable {
    var weightLbs: Double
    var bmi: Double?
    var bodyFatPct: Double?
    var leanMassLbs: Double?
    var measuredAt: Date?

    /// A one-line composition summary for the day the scale ran, e.g.
    /// "24.1% fat · 99.7 lean". Nil when no composition data came through.
    var compositionLine: String? {
        var parts: [String] = []
        if let bodyFatPct { parts.append("\(trim(bodyFatPct))% fat") }
        if let leanMassLbs { parts.append("\(trim(leanMassLbs)) lean") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct ActivitySummary: Codable, Sendable {
    var moveKcal: Int
    var moveGoalKcal: Int = 500
    var exerciseMin: Int
    var exerciseGoalMin: Int = 30
    var standHours: Int
    var standGoalHours: Int = 12
    var steps: Int?
}

enum WorkoutStatus: String, Codable, Sendable {
    case done, partial, skipped, rest
}

struct WorkoutEntry: Codable, Sendable {
    var status: WorkoutStatus
    var template: String?
    var title: String?
    var startedAt: Date?
    var durationMin: Int?
    var exercises: [ExerciseEntry] = []
}

struct ExerciseEntry: Codable, Identifiable, Sendable {
    var name: String
    var sets: [SetEntry]?
    var durationMin: Int?
    var inclinePct: Double?
    var speedMph: Double?

    var id: String { name }

    /// Ledger notation: "8×95 8×95 6×100" or "20m @ 12%".
    var notation: String {
        if let sets {
            return sets.map { "\($0.reps)×\(Self.trim($0.weightLbs))" }.joined(separator: "  ")
        }
        var parts: [String] = []
        if let durationMin { parts.append("\(durationMin)m") }
        if let inclinePct { parts.append("@ \(Self.trim(inclinePct))%") }
        if let speedMph { parts.append("\(Self.trim(speedMph)) mph") }
        return parts.joined(separator: " ")
    }

    private static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

struct SetEntry: Codable, Hashable, Sendable {
    var reps: Int
    var weightLbs: Double
}

struct FoodEntry: Codable, Identifiable, Sendable {
    var at: String
    var text: String?
    var recipe: String?
    var photo: String?

    var id: String { at + (text ?? recipe ?? photo ?? "") }
}

enum PicPose: String, Codable, Sendable {
    case front, side, back, other
}

struct ProgressPic: Codable, Identifiable, Sendable {
    var path: String
    var pose: PicPose

    var id: String { path }
}

/// How a day renders on the Spine — the app's consistency record.
enum DayMark: Sendable {
    case trained   // full-height ink stroke
    case logged    // mid-height stroke
    case empty     // faint dot

    init(log: DailyLog?) {
        guard let log else { self = .empty; return }
        if let workout = log.workout, workout.status == .done || workout.status == .partial {
            self = .trained
        } else if log.metrics != nil || !log.food.isEmpty || !log.pics.isEmpty {
            self = .logged
        } else {
            self = .empty
        }
    }
}

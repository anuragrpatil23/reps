import Foundation

/// A daily meal template: the staple foods you eat every day, so the two meals
/// that never change don't need re-logging. Grouped by phase (cut/bulk/…) so you
/// switch plans when your phase does — one active at a time, like `Program`.
///
/// Stored one-per-file at `sffit/meal-plans/<key>.md`. Each staple is a plain
/// `FoodEntry` (food_id + servings + a default time), reused verbatim when the
/// plan pre-fills a day.
struct MealPlan: Identifiable, Sendable, Equatable {
    var key: String
    var title: String
    var phase: TrainingPhase
    var staples: [FoodEntry]

    var id: String { key }
}

import Foundation

/// Today's energy picture: calories out (resting + movement), a suggested intake
/// to hold a deficit, and macro targets — all derived from your body composition
/// and a few tunable knobs. Every suggestion has a sensible default the user can
/// override in Settings; nothing here is prescriptive, it's a target to aim at.
struct EnergyBudget {
    // Measured inputs (most-recent weigh-in + today's activity + what you ate).
    var leanMassLbs: Double?
    var weightLbs: Double?
    var activeKcal: Double
    var intake: Macros

    // Tunable knobs (defaults live in Settings; 0 baseline means "auto").
    var baselineOverride: Double   // resting burn override; 0 → Katch–McArdle
    var dailyDeficit: Double       // kcal/day below maintenance
    var proteinPerLbLean: Double   // protein target, g per lb lean mass
    var fatPerLbBody: Double       // fat floor, g per lb bodyweight

    private static let lbToKg = 0.453592

    /// Resting burn: the user's override if set, else Katch–McArdle from lean
    /// mass — the most personal RMR formula, which needs body composition.
    var baselineBurn: Double? {
        if baselineOverride > 0 { return baselineOverride }
        guard let lean = leanMassLbs else { return nil }
        return 370 + 21.6 * (lean * Self.lbToKg)
    }

    /// Total calories out = resting + active energy logged by Health.
    var caloriesOut: Double? {
        baselineBurn.map { $0 + activeKcal }
    }

    /// Suggested intake to sit `dailyDeficit` below maintenance.
    var targetCalories: Double? {
        caloriesOut.map { max($0 - dailyDeficit, 0) }
    }

    /// Today's actual gap, out − in. Positive = deficit, negative = surplus.
    var balance: Double? {
        caloriesOut.map { $0 - intake.calories }
    }

    var proteinTarget: Double? { leanMassLbs.map { $0 * proteinPerLbLean } }
    var fatTarget: Double? { weightLbs.map { $0 * fatPerLbBody } }

    /// Carbs fill whatever calories remain after protein (4 kcal/g) and fat (9).
    var carbTarget: Double? {
        guard let tc = targetCalories, let p = proteinTarget, let f = fatTarget else { return nil }
        return max((tc - (p * 4 + f * 9)) / 4, 0)
    }

    /// Enough data to show anything (need a resting burn at minimum).
    var hasEnergy: Bool { caloriesOut != nil }
}

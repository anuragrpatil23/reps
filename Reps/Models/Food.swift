import Foundation

/// One item in the personal food database (sffood/data/foods.csv). Macros are
/// per serving; a logged meal is a food × a serving count.
struct Food: Identifiable, Sendable, Equatable {
    var id: String            // stable slug, referenced by logged meals
    var name: String
    var servingDesc: String   // "1 cup (170g)"
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var barcode: String?
    var updatedAt: Date?

    var macros: Macros {
        Macros(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }

    /// A URL-safe slug from a name, for the id.
    static func slug(for name: String) -> String {
        let lowered = name.lowercased()
        let mapped = lowered.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let collapsed = String(mapped).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? UUID().uuidString : collapsed
    }
}

/// A macro tally — summable and scalable.
struct Macros: Sendable, Equatable {
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0

    var isEmpty: Bool { calories == 0 && proteinG == 0 && carbsG == 0 && fatG == 0 }

    func scaled(by factor: Double) -> Macros {
        Macros(calories: calories * factor, proteinG: proteinG * factor,
               carbsG: carbsG * factor, fatG: fatG * factor)
    }

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(calories: lhs.calories + rhs.calories, proteinG: lhs.proteinG + rhs.proteinG,
               carbsG: lhs.carbsG + rhs.carbsG, fatG: lhs.fatG + rhs.fatG)
    }
}

/// Structured nutrition parsed from a label (OCR → model/heuristic). Every
/// field optional — the user confirms/fills the rest in the form.
struct NutritionFacts: Sendable {
    var name: String?
    var servingDesc: String?
    var calories: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
}

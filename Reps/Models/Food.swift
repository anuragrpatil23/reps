import Foundation

/// One item in the personal food database (sffood/data/foods.csv). Nutrition is
/// per serving; a logged meal is a food × a serving count. `servingGrams` (the
/// weight of one serving) lets the logger work in grams as well as servings.
struct Food: Identifiable, Sendable, Equatable {
    var id: String            // stable slug, referenced by logged meals
    var name: String
    var servingDesc: String   // "1 cup (170g)"
    var servingGrams: Double? // weight of one serving, for gram-based logging
    var servingPieces: Double? // pieces in one serving ("3 crackers"), for piece-based logging
    var nutrition: Macros     // full per-serving nutrition (macros + micros)
    var barcode: String?
    var updatedAt: Date?

    /// Back-compat accessors so call sites keep reading the four headline macros.
    var calories: Double { nutrition.calories }
    var proteinG: Double { nutrition.proteinG }
    var carbsG: Double { nutrition.carbsG }
    var fatG: Double { nutrition.fatG }

    var macros: Macros { nutrition }

    /// A human serving label for lists: the scanned description if present, else
    /// composed from the structured weight/pieces ("3 pcs · 30 g").
    var servingLabel: String {
        if !servingDesc.isEmpty { return servingDesc }
        var parts: [String] = []
        if let p = servingPieces, p > 0 {
            parts.append("\(p.formatted(.number.precision(.fractionLength(0...1)))) pc\(p == 1 ? "" : "s")")
        }
        if let g = servingGrams, g > 0 {
            parts.append("\(g.formatted(.number.precision(.fractionLength(0...1)))) g")
        }
        return parts.joined(separator: " · ")
    }

    /// Tidy a scanned name for display: OCR'd labels are usually shouty ALL-CAPS,
    /// so re-case any fully-uppercase word to Title Case ("KIND BAR" → "Kind Bar").
    /// Words that are already mixed-case ("McVitie's") are intentional styling and
    /// left as typed.
    static func normalizedName(_ raw: String) -> String {
        raw.split(separator: " ").map { word -> String in
            let s = String(word)
            let letters = s.filter(\.isLetter)
            guard !letters.isEmpty, letters.allSatisfy(\.isUppercase) else { return s }
            return s.prefix(1) + s.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    /// A URL-safe slug from a name, for the id.
    static func slug(for name: String) -> String {
        let lowered = name.lowercased()
        let mapped = lowered.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let collapsed = String(mapped).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? UUID().uuidString : collapsed
    }
}

/// A full nutrition tally — every value a US Nutrition Facts panel carries.
/// Summable and scalable, so a day's total and a servings multiplier are just
/// `+` and `scaled(by:)`. Units live in the field names (g / mg / mcg).
struct Macros: Sendable, Equatable {
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var satFatG: Double = 0
    var transFatG: Double = 0
    var cholesterolMg: Double = 0
    var sodiumMg: Double = 0
    var fiberG: Double = 0
    var totalSugarsG: Double = 0
    var addedSugarsG: Double = 0
    var vitaminDMcg: Double = 0
    var calciumMg: Double = 0
    var ironMg: Double = 0
    var potassiumMg: Double = 0

    var isEmpty: Bool {
        calories == 0 && proteinG == 0 && carbsG == 0 && fatG == 0 && satFatG == 0
            && transFatG == 0 && cholesterolMg == 0 && sodiumMg == 0 && fiberG == 0
            && totalSugarsG == 0 && addedSugarsG == 0 && vitaminDMcg == 0
            && calciumMg == 0 && ironMg == 0 && potassiumMg == 0
    }

    func scaled(by factor: Double) -> Macros {
        map { $0 * factor }
    }

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(
            calories: lhs.calories + rhs.calories, proteinG: lhs.proteinG + rhs.proteinG,
            carbsG: lhs.carbsG + rhs.carbsG, fatG: lhs.fatG + rhs.fatG,
            satFatG: lhs.satFatG + rhs.satFatG, transFatG: lhs.transFatG + rhs.transFatG,
            cholesterolMg: lhs.cholesterolMg + rhs.cholesterolMg, sodiumMg: lhs.sodiumMg + rhs.sodiumMg,
            fiberG: lhs.fiberG + rhs.fiberG, totalSugarsG: lhs.totalSugarsG + rhs.totalSugarsG,
            addedSugarsG: lhs.addedSugarsG + rhs.addedSugarsG, vitaminDMcg: lhs.vitaminDMcg + rhs.vitaminDMcg,
            calciumMg: lhs.calciumMg + rhs.calciumMg, ironMg: lhs.ironMg + rhs.ironMg,
            potassiumMg: lhs.potassiumMg + rhs.potassiumMg
        )
    }

    /// Apply a transform to every field (used for scaling).
    private func map(_ t: (Double) -> Double) -> Macros {
        Macros(
            calories: t(calories), proteinG: t(proteinG), carbsG: t(carbsG), fatG: t(fatG),
            satFatG: t(satFatG), transFatG: t(transFatG), cholesterolMg: t(cholesterolMg),
            sodiumMg: t(sodiumMg), fiberG: t(fiberG), totalSugarsG: t(totalSugarsG),
            addedSugarsG: t(addedSugarsG), vitaminDMcg: t(vitaminDMcg), calciumMg: t(calciumMg),
            ironMg: t(ironMg), potassiumMg: t(potassiumMg)
        )
    }
}

/// Structured nutrition parsed from a label (OCR → model/heuristic). Every
/// field optional — the user confirms/fills the rest in the form.
struct NutritionFacts: Sendable {
    var name: String? = nil
    var servingDesc: String? = nil
    var servingGrams: Double? = nil
    var servingPieces: Double? = nil
    var calories: Double? = nil
    var proteinG: Double? = nil
    var carbsG: Double? = nil
    var fatG: Double? = nil
    var satFatG: Double? = nil
    var transFatG: Double? = nil
    var cholesterolMg: Double? = nil
    var sodiumMg: Double? = nil
    var fiberG: Double? = nil
    var totalSugarsG: Double? = nil
    var addedSugarsG: Double? = nil
    var vitaminDMcg: Double? = nil
    var calciumMg: Double? = nil
    var ironMg: Double? = nil
    var potassiumMg: Double? = nil

    /// Return self with every missing field (nil, or empty string for text)
    /// filled from `other`. Lets the deterministic heuristic backstop whatever
    /// the on-device model happened to drop — no single miss zeroes a field.
    func filling(from other: NutritionFacts) -> NutritionFacts {
        func text(_ a: String?, _ b: String?) -> String? {
            if let a, !a.isEmpty { return a }
            return b
        }
        var f = self
        f.name = text(f.name, other.name)
        f.servingDesc = text(f.servingDesc, other.servingDesc)
        f.servingGrams = f.servingGrams ?? other.servingGrams
        f.servingPieces = f.servingPieces ?? other.servingPieces
        f.calories = f.calories ?? other.calories
        f.proteinG = f.proteinG ?? other.proteinG
        f.carbsG = f.carbsG ?? other.carbsG
        f.fatG = f.fatG ?? other.fatG
        f.satFatG = f.satFatG ?? other.satFatG
        f.transFatG = f.transFatG ?? other.transFatG
        f.cholesterolMg = f.cholesterolMg ?? other.cholesterolMg
        f.sodiumMg = f.sodiumMg ?? other.sodiumMg
        f.fiberG = f.fiberG ?? other.fiberG
        f.totalSugarsG = f.totalSugarsG ?? other.totalSugarsG
        f.addedSugarsG = f.addedSugarsG ?? other.addedSugarsG
        f.vitaminDMcg = f.vitaminDMcg ?? other.vitaminDMcg
        f.calciumMg = f.calciumMg ?? other.calciumMg
        f.ironMg = f.ironMg ?? other.ironMg
        f.potassiumMg = f.potassiumMg ?? other.potassiumMg
        return f
    }
}

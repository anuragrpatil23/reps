import Foundation

/// Heuristic parse of OCR'd nutrition-label text into structured facts. This is
/// the reliable baseline (and the fallback when the on-device model isn't
/// available); the form it fills is always editable. Every line of a US
/// Nutrition Facts panel is probed — macros, the fat/carb breakdown, and the
/// four mandatory micros (vitamin D, calcium, iron, potassium).
enum NutritionLabelParser {
    static func parse(_ lines: [String]) -> NutritionFacts {
        var facts = NutritionFacts()
        facts.calories = number(near: ["calories", "calorie", "energy"], in: lines)
        facts.proteinG = grams(near: ["protein"], in: lines)
        facts.carbsG = grams(near: ["total carbohydrate", "carbohydrate", "carbs", "carb"], in: lines)
        // "saturated" / "trans" before "fat" so the generic "fat" match doesn't eat them.
        facts.satFatG = grams(near: ["saturated fat", "saturated"], in: lines)
        facts.transFatG = grams(near: ["trans fat", "trans"], in: lines)
        facts.fatG = grams(near: ["total fat"], in: lines) ?? gramsExcluding(["saturated", "trans"], near: ["fat"], in: lines)
        facts.fiberG = grams(near: ["dietary fiber", "fiber", "fibre"], in: lines)
        facts.addedSugarsG = grams(near: ["added sugars", "includes"], in: lines)
        facts.totalSugarsG = grams(near: ["total sugars", "sugars", "sugar"], in: lines)
        facts.cholesterolMg = milligrams(near: ["cholesterol"], in: lines)
        facts.sodiumMg = milligrams(near: ["sodium"], in: lines)
        facts.potassiumMg = milligrams(near: ["potassium"], in: lines)
        facts.calciumMg = milligrams(near: ["calcium"], in: lines)
        facts.ironMg = milligrams(near: ["iron"], in: lines)
        facts.vitaminDMcg = micrograms(near: ["vitamin d", "vit d"], in: lines)
        facts.servingsPerContainer = number(near: ["servings per container", "servings per"], in: lines)
        facts.servingDesc = value(after: ["serving size", "serving"], in: lines)
        facts.servingGrams = facts.servingDesc.flatMap(gramWeight)
        return facts
    }

    /// First numeric value on a line mentioning any keyword.
    private static func number(near keywords: [String], in lines: [String]) -> Double? {
        for line in lines where keywords.contains(where: line.lowercased().contains) {
            if let match = firstNumber(in: line) { return match }
        }
        return nil
    }

    /// First "<n> g" value on a keyword line (falls back to any number).
    private static func grams(near keywords: [String], in lines: [String]) -> Double? {
        for line in lines where keywords.contains(where: line.lowercased().contains) {
            if let g = firstNumber(in: line, unit: "g") { return g }
            if let n = firstNumber(in: line) { return n }
        }
        return nil
    }

    /// Grams on a keyword line, but skip lines that also mention an excluded word
    /// (so plain "fat" doesn't capture the "saturated fat" / "trans fat" rows).
    private static func gramsExcluding(_ excluded: [String], near keywords: [String], in lines: [String]) -> Double? {
        for line in lines {
            let lower = line.lowercased()
            guard keywords.contains(where: lower.contains),
                  !excluded.contains(where: lower.contains) else { continue }
            if let g = firstNumber(in: line, unit: "g") { return g }
            if let n = firstNumber(in: line) { return n }
        }
        return nil
    }

    private static func milligrams(near keywords: [String], in lines: [String]) -> Double? {
        for line in lines where keywords.contains(where: line.lowercased().contains) {
            if let mg = firstNumber(in: line, unit: "mg") { return mg }
            if let n = firstNumber(in: line) { return n }
        }
        return nil
    }

    private static func micrograms(near keywords: [String], in lines: [String]) -> Double? {
        for line in lines where keywords.contains(where: line.lowercased().contains) {
            if let mcg = firstNumber(in: line, unit: "mcg") { return mcg }
            if let n = firstNumber(in: line) { return n }
        }
        return nil
    }

    private static func value(after keywords: [String], in lines: [String]) -> String? {
        for line in lines {
            let lower = line.lowercased()
            guard let keyword = keywords.first(where: lower.contains),
                  let range = lower.range(of: keyword) else { continue }
            let tail = String(line[range.upperBound...]).trimmingCharacters(
                in: CharacterSet(charactersIn: " :\t"))
            if !tail.isEmpty { return tail }
        }
        return nil
    }

    /// Pull a gram weight out of a serving description like "1 cup (170g)".
    private static func gramWeight(_ text: String) -> Double? {
        firstNumber(in: text, unit: "g")
    }

    /// First number in `text`. With `unit`, requires that unit to follow (and
    /// rejects `mg`/`mcg` when the unit is `g` so grams and milligrams don't mix).
    private static func firstNumber(in text: String, unit: String? = nil) -> Double? {
        let pattern: String
        if let unit {
            let boundary = unit == "g" ? #"(?![a-z])"# : ""   // "g" must not be the start of "mg"/"mcg"
            pattern = #"(\d+(?:\.\d+)?)\s*"# + NSRegularExpression.escapedPattern(for: unit) + boundary
        } else {
            pattern = #"(\d+(?:\.\d+)?)"#
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[valueRange])
    }
}

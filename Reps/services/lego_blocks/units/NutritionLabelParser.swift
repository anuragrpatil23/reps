import Foundation

/// Heuristic parse of OCR'd nutrition-label text into structured facts. This is
/// the reliable baseline (and the fallback when the on-device model isn't
/// available); the form it fills is always editable. Every line of a US
/// Nutrition Facts panel is probed — macros, the fat/carb breakdown, and the
/// four mandatory micros (vitamin D, calcium, iron, potassium).
enum NutritionLabelParser {
    static func parse(_ lines: [String]) -> NutritionFacts {
        var facts = NutritionFacts()
        facts.calories = calories(in: lines)
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
        facts.potassiumMg = milligrams(near: ["potassium", "potas"], in: lines)
        facts.calciumMg = milligrams(near: ["calcium"], in: lines)
        facts.ironMg = milligrams(near: ["iron"], in: lines)
        facts.vitaminDMcg = micrograms(near: ["vitamin d", "vit d", "vit. d"], in: lines)
        facts.servingDesc = value(after: ["serving size", "serving"], in: lines)
        facts.servingGrams = facts.servingDesc.flatMap(gramWeight)
        facts.servingPieces = pieceCount(from: facts.servingDesc)
        facts.name = guessName(from: lines)
        return facts
    }

    /// Volume/weight units — a serving measured in these isn't a piece count.
    private static let measuredUnits: Set<String> = [
        "cup", "cups", "tbsp", "tbsps", "tablespoon", "tablespoons",
        "tsp", "tsps", "teaspoon", "teaspoons", "oz", "ounce", "ounces",
        "fl", "ml", "l", "liter", "liters", "litre", "litres",
        "g", "gram", "grams", "kg", "mg", "mcg", "cc",
    ]

    /// Pieces in a serving from a description like "3 crackers (30g)" — a leading
    /// count followed by a countable word (not a cup/gram/oz measure).
    private static func pieceCount(from desc: String?) -> Double? {
        guard let desc,
              let regex = try? NSRegularExpression(pattern: #"^\s*(\d+(?:\.\d+)?)\s*([a-zA-Z]+)"#),
              let m = regex.firstMatch(in: desc, range: NSRange(desc.startIndex..., in: desc)),
              let nRange = Range(m.range(at: 1), in: desc),
              let uRange = Range(m.range(at: 2), in: desc),
              let n = Double(desc[nRange]) else { return nil }
        return measuredUnits.contains(desc[uRange].lowercased()) ? nil : n
    }

    /// Words that flag a line as part of the Nutrition Facts panel (or other
    /// packaging boilerplate) rather than the product name.
    private static let panelKeywords = [
        "nutrition", "fact", "serving", "amount", "calorie", "daily value",
        "per container", "total fat", "saturated", "trans", "cholesterol",
        "sodium", "carbohydrate", "carb", "dietary", "fiber", "fibre", "sugar",
        "protein", "vitamin", "calcium", "iron", "potassium", "includes",
        "added", "ingredient", "contains", "allerg", "distributed",
        "manufactured", "net wt", "net weight", "www", ".com", "%",
    ]

    /// Best-guess product name. Nutrition panels rarely label the product, so we
    /// take the most name-like line: skip panel/boilerplate lines and number
    /// rows, then take the first mostly-alphabetic line — with reading order now
    /// top-to-bottom, that's usually the brand/product line above the facts.
    static func guessName(from lines: [String]) -> String? {
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (3...40).contains(line.count) else { continue }

            let lower = line.lowercased()
            if panelKeywords.contains(where: lower.contains) { continue }

            let letters = line.filter(\.isLetter).count
            let digits = line.filter(\.isNumber).count
            // Need real words and not a numbers/units row.
            guard letters >= 3, letters > digits * 2 else { continue }

            return line
        }
        return nil
    }

    /// Calories are the exception on a US panel: the big number usually lands on
    /// the line *below* the word "Calories" (OCR splits them), so probe the
    /// keyword line and, failing that, the next couple of lines for a standalone
    /// number — but only a lone number, so we don't grab "Total Fat 8g" by mistake.
    private static func calories(in lines: [String]) -> Double? {
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard lower.contains("calorie") || lower.contains("energy") else { continue }
            if lower.contains("from fat") { continue }   // old-label sub-line, not the headline
            if let kcal = firstNumber(in: line, unit: "kcal") { return kcal }
            if let n = firstNumber(in: line) { return n }
            let upper = min(i + 2, lines.count - 1)
            if upper >= i + 1 {
                for j in (i + 1)...upper where isLoneNumber(lines[j]) {
                    if let n = firstNumber(in: lines[j]) { return n }
                }
            }
        }
        return nil
    }

    /// True when a line is nothing but a number (optionally with a "kcal" unit) —
    /// i.e. the standalone calories value, not a "Total Fat 8g" nutrient row.
    private static func isLoneNumber(_ s: String) -> Bool {
        let stripped = s.lowercased()
            .replacingOccurrences(of: "kcal", with: "")
            .trimmingCharacters(in: .whitespaces)
        return !stripped.isEmpty && stripped.allSatisfy { $0.isNumber || $0 == "." }
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

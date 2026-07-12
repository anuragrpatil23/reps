import Foundation

/// Heuristic parse of OCR'd nutrition-label text into structured facts. This is
/// the reliable baseline (and the fallback when the on-device model isn't
/// available); the form it fills is always editable.
enum NutritionLabelParser {
    static func parse(_ lines: [String]) -> NutritionFacts {
        var facts = NutritionFacts()
        facts.calories = number(near: ["calories", "calorie", "energy"], in: lines, allowNoUnit: true)
        facts.proteinG = grams(near: ["protein"], in: lines)
        facts.carbsG = grams(near: ["total carbohydrate", "carbohydrate", "carbs", "carb"], in: lines)
        facts.fatG = grams(near: ["total fat", "fat"], in: lines)
        facts.servingDesc = value(after: ["serving size", "serving"], in: lines)
        return facts
    }

    /// First numeric value on a line mentioning any keyword.
    private static func number(near keywords: [String], in lines: [String], allowNoUnit: Bool) -> Double? {
        for line in lines {
            let lower = line.lowercased()
            guard keywords.contains(where: lower.contains) else { continue }
            if let match = firstNumber(in: line) { return match }
        }
        return nil
    }

    /// First "<n> g" value on a line mentioning any keyword (prefers a gram value).
    private static func grams(near keywords: [String], in lines: [String]) -> Double? {
        for line in lines {
            let lower = line.lowercased()
            guard keywords.contains(where: lower.contains) else { continue }
            if let g = firstNumber(in: line, requireGramSuffix: true) { return g }
            if let n = firstNumber(in: line) { return n }
        }
        return nil
    }

    private static func value(after keywords: [String], in lines: [String]) -> String? {
        for line in lines {
            let lower = line.lowercased()
            guard let keyword = keywords.first(where: lower.contains) else { continue }
            if let range = lower.range(of: keyword) {
                let tail = String(line[range.upperBound...]).trimmingCharacters(
                    in: CharacterSet(charactersIn: " :\t"))
                if !tail.isEmpty { return tail }
            }
        }
        return nil
    }

    private static func firstNumber(in text: String, requireGramSuffix: Bool = false) -> Double? {
        let pattern = requireGramSuffix ? #"(\d+(?:\.\d+)?)\s*g"# : #"(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[valueRange])
    }
}

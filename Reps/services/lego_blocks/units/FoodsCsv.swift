import Foundation

/// CSV codec for the personal food database (sffood/data/foods.csv). Unlike the
/// telemetry CSVs, food names / serving descriptions can contain commas, so
/// this does proper RFC-style quoting.
///
/// Parsing is header-driven (column name → index), so old files written with
/// the original 9-column header still load and simply leave the new nutrition
/// fields at zero — an additive schema change, no version bump (contract §7).
@MainActor
enum FoodsCsv {
    static let path = "sffood/data/foods.csv"

    /// Column order for the file we write. Read order comes from each file's own
    /// header row, so this can grow without breaking older files.
    private static let columns = [
        "id", "name", "serving_desc", "serving_grams", "servings_per_container",
        "calories", "protein_g", "carbs_g", "fat_g",
        "sat_fat_g", "trans_fat_g", "cholesterol_mg", "sodium_mg",
        "fiber_g", "total_sugars_g", "added_sugars_g",
        "vitamin_d_mcg", "calcium_mg", "iron_mg", "potassium_mg",
        "barcode", "updated_at",
    ]

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    static func format(_ foods: [Food]) -> String {
        var lines = [columns.joined(separator: ",")]
        for food in foods.sorted(by: { $0.name.lowercased() < $1.name.lowercased() }) {
            let n = food.nutrition
            let cells: [String: String] = [
                "id": food.id,
                "name": food.name,
                "serving_desc": food.servingDesc,
                "serving_grams": food.servingGrams.map(num) ?? "",
                "servings_per_container": food.servingsPerContainer.map(num) ?? "",
                "calories": num(n.calories),
                "protein_g": num(n.proteinG),
                "carbs_g": num(n.carbsG),
                "fat_g": num(n.fatG),
                "sat_fat_g": num(n.satFatG),
                "trans_fat_g": num(n.transFatG),
                "cholesterol_mg": num(n.cholesterolMg),
                "sodium_mg": num(n.sodiumMg),
                "fiber_g": num(n.fiberG),
                "total_sugars_g": num(n.totalSugarsG),
                "added_sugars_g": num(n.addedSugarsG),
                "vitamin_d_mcg": num(n.vitaminDMcg),
                "calcium_mg": num(n.calciumMg),
                "iron_mg": num(n.ironMg),
                "potassium_mg": num(n.potassiumMg),
                "barcode": food.barcode ?? "",
                "updated_at": food.updatedAt.map(isoFormatter.string) ?? "",
            ]
            lines.append(columns.map { escape(cells[$0] ?? "") }.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func parse(_ text: String) -> [Food] {
        let rows = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        guard let headerLine = rows.first, headerLine.hasPrefix("id,") else { return [] }
        let header = fields(headerLine)
        let index = Dictionary(header.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })

        return rows.dropFirst().compactMap { line in
            let c = fields(line)
            func str(_ column: String) -> String {
                guard let i = index[column], i < c.count else { return "" }
                return c[i]
            }
            func dbl(_ column: String) -> Double { Double(str(column)) ?? 0 }
            func optDbl(_ column: String) -> Double? { let s = str(column); return s.isEmpty ? nil : Double(s) }

            let id = str("id")
            guard !id.isEmpty else { return nil }
            let nutrition = Macros(
                calories: dbl("calories"), proteinG: dbl("protein_g"),
                carbsG: dbl("carbs_g"), fatG: dbl("fat_g"),
                satFatG: dbl("sat_fat_g"), transFatG: dbl("trans_fat_g"),
                cholesterolMg: dbl("cholesterol_mg"), sodiumMg: dbl("sodium_mg"),
                fiberG: dbl("fiber_g"), totalSugarsG: dbl("total_sugars_g"),
                addedSugarsG: dbl("added_sugars_g"), vitaminDMcg: dbl("vitamin_d_mcg"),
                calciumMg: dbl("calcium_mg"), ironMg: dbl("iron_mg"),
                potassiumMg: dbl("potassium_mg")
            )
            let barcode = str("barcode")
            let updated = str("updated_at")
            return Food(
                id: id, name: str("name"), servingDesc: str("serving_desc"),
                servingGrams: optDbl("serving_grams"),
                servingsPerContainer: optDbl("servings_per_container"),
                nutrition: nutrition,
                barcode: barcode.isEmpty ? nil : barcode,
                updatedAt: updated.isEmpty ? nil : isoFormatter.date(from: updated)
            )
        }
    }

    // MARK: - RFC-ish CSV field quoting

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func fields(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var pending = iterator.next()
        while let ch = pending {
            pending = iterator.next()
            if inQuotes {
                if ch == "\"" {
                    if pending == "\"" { current.append("\""); pending = iterator.next() }
                    else { inQuotes = false }
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == "," {
                result.append(current); current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }

    private static func num(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String((value * 10).rounded() / 10)
    }
}

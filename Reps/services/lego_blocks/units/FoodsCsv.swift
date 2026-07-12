import Foundation

/// CSV codec for the personal food database (sffood/data/foods.csv). Unlike the
/// telemetry CSVs, food names / serving descriptions can contain commas, so
/// this does proper RFC-style quoting.
@MainActor
enum FoodsCsv {
    static let path = "sffood/data/foods.csv"
    private static let header = "id,name,serving_desc,calories,protein_g,carbs_g,fat_g,barcode,updated_at"

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    static func format(_ foods: [Food]) -> String {
        var lines = [header]
        for food in foods.sorted(by: { $0.name.lowercased() < $1.name.lowercased() }) {
            lines.append([
                food.id,
                food.name,
                food.servingDesc,
                num(food.calories),
                num(food.proteinG),
                num(food.carbsG),
                num(food.fatG),
                food.barcode ?? "",
                food.updatedAt.map(isoFormatter.string) ?? "",
            ].map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func parse(_ text: String) -> [Food] {
        text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix("id,name") }
            .compactMap { line in
                let c = fields(line)
                guard c.count >= 7, !c[0].isEmpty else { return nil }
                return Food(
                    id: c[0],
                    name: c[1],
                    servingDesc: c[2],
                    calories: Double(c[3]) ?? 0,
                    proteinG: Double(c[4]) ?? 0,
                    carbsG: Double(c[5]) ?? 0,
                    fatG: Double(c[6]) ?? 0,
                    barcode: c.count > 7 && !c[7].isEmpty ? c[7] : nil,
                    updatedAt: c.count > 8 ? isoFormatter.date(from: c[8]) : nil
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

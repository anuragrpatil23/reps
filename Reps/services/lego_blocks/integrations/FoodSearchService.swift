import Foundation

/// Online food lookup for the new-food page: type a name, get candidate items
/// with approximate nutrition to prefill the form. Open Food Facts leads
/// (strong on branded/packaged items, no key), USDA FoodData Central backfills
/// generic whole foods. The user still confirms everything before saving, so
/// coverage matters more than precision here.
///
/// This is the app's only network call — nothing else leaves the device. A
/// lookup sends just the typed query, and only when the user taps "Search
/// online".
enum FoodSearchService {
    /// USDA needs a free key (https://fdc.nal.usda.gov/api-key-signup.html).
    /// `DEMO_KEY` works out of the box but is rate-limited (≈30/hr per IP);
    /// swap in a personal key for real use.
    private static let usdaKey = "DEMO_KEY"

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    /// Candidate foods for `query`, most-relevant first. Open Food Facts hits
    /// lead; USDA results follow. Network/parse failures yield an empty list
    /// from that source rather than throwing — a slow API never blocks the other.
    static func search(_ query: String) async -> [FoodSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        async let off = openFoodFacts(trimmed)
        async let usda = usdaFoods(trimmed)
        let (offResults, usdaResults) = await (off, usda)

        // Drop near-duplicate names across the two sources (OFF wins ties).
        var seen = Set<String>()
        return (offResults + usdaResults).filter { result in
            let key = result.name.lowercased()
            return seen.insert(key).inserted
        }
    }

    // MARK: - Open Food Facts

    private static func openFoodFacts(_ query: String) async -> [FoodSearchResult] {
        var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            .init(name: "search_terms", value: query),
            .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"),
            .init(name: "json", value: "1"),
            .init(name: "page_size", value: "20"),
            .init(name: "fields", value: "product_name,brands,serving_size,serving_quantity,nutriments")
        ]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        // Open Food Facts asks clients to identify themselves.
        req.setValue("Reps/1.0 (iOS; personal food logger)", forHTTPHeaderField: "User-Agent")

        guard let json = await fetchJSON(req) as? [String: Any],
              let products = json["products"] as? [[String: Any]] else { return [] }

        return products.compactMap { product in
            guard let rawName = product["product_name"] as? String,
                  !rawName.trimmingCharacters(in: .whitespaces).isEmpty,
                  let nutriments = product["nutriments"] as? [String: Any] else { return nil }

            // Nutriments are per 100 g; scale to the serving when one is known.
            let servingG = num(product["serving_quantity"])
            let factor = (servingG ?? 0) > 0 ? servingG! / 100 : 1
            let servingDesc = (product["serving_size"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (servingG.map { "\(trim($0)) g" } ?? "per 100 g")

            var f = NutritionFacts()
            f.name = rawName
            f.servingDesc = servingDesc
            f.servingGrams = servingG ?? 100
            f.calories = scale(num(nutriments["energy-kcal_100g"]), factor)
            f.proteinG = scale(num(nutriments["proteins_100g"]), factor)
            f.carbsG = scale(num(nutriments["carbohydrates_100g"]), factor)
            f.fatG = scale(num(nutriments["fat_100g"]), factor)
            f.satFatG = scale(num(nutriments["saturated-fat_100g"]), factor)
            f.transFatG = scale(num(nutriments["trans-fat_100g"]), factor)
            // OFF reports these in grams; the form wants mg / mcg.
            f.cholesterolMg = scale(num(nutriments["cholesterol_100g"]).map { $0 * 1000 }, factor)
            f.sodiumMg = scale(num(nutriments["sodium_100g"]).map { $0 * 1000 }, factor)
            f.fiberG = scale(num(nutriments["fiber_100g"]), factor)
            f.totalSugarsG = scale(num(nutriments["sugars_100g"]), factor)
            f.addedSugarsG = scale(num(nutriments["added-sugars_100g"]), factor)
            f.vitaminDMcg = scale(num(nutriments["vitamin-d_100g"]).map { $0 * 1_000_000 }, factor)
            f.calciumMg = scale(num(nutriments["calcium_100g"]).map { $0 * 1000 }, factor)
            f.ironMg = scale(num(nutriments["iron_100g"]).map { $0 * 1000 }, factor)
            f.potassiumMg = scale(num(nutriments["potassium_100g"]).map { $0 * 1000 }, factor)

            let brand = (product["brands"] as? String)?
                .split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
            return FoodSearchResult(
                id: "off:\(rawName):\(brand ?? ""):\(servingDesc)",
                name: Food.normalizedName(rawName), brand: brand,
                source: "Open Food Facts", facts: f
            )
        }
    }

    // MARK: - USDA FoodData Central

    private static func usdaFoods(_ query: String) async -> [FoodSearchResult] {
        var comps = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        comps.queryItems = [
            .init(name: "query", value: query),
            .init(name: "pageSize", value: "15"),
            .init(name: "api_key", value: usdaKey)
        ]
        guard let url = comps.url else { return [] }

        guard let json = await fetchJSON(URLRequest(url: url)) as? [String: Any],
              let foods = json["foods"] as? [[String: Any]] else { return [] }

        return foods.compactMap { food in
            guard let desc = food["description"] as? String,
                  let nutrients = food["foodNutrients"] as? [[String: Any]] else { return nil }

            // USDA nutrients are per 100 g; scale to serving when given in grams.
            let unit = (food["servingSizeUnit"] as? String)?.lowercased() ?? ""
            let isGrams = unit == "g" || unit == "gram" || unit == "grams"
            let gramServing = isGrams ? num(food["servingSize"]) : nil
            let factor = (gramServing ?? 0) > 0 ? gramServing! / 100 : 1

            // Index nutrient values by their USDA nutrient number.
            var byNumber: [String: Double] = [:]
            for n in nutrients {
                let number = (n["nutrientNumber"] as? String) ?? (n["number"] as? String)
                if let number, let value = num(n["value"]) { byNumber[number] = value }
            }
            func v(_ number: String) -> Double? { byNumber[number] }

            var f = NutritionFacts()
            f.name = desc
            f.servingDesc = (gramServing ?? 0) > 0 ? "\(trim(gramServing!)) g" : "per 100 g"
            f.servingGrams = gramServing ?? 100
            f.calories = scale(v("208"), factor)
            f.proteinG = scale(v("203"), factor)
            f.carbsG = scale(v("205"), factor)
            f.fatG = scale(v("204"), factor)
            f.satFatG = scale(v("606"), factor)
            f.transFatG = scale(v("605"), factor)
            f.cholesterolMg = scale(v("601"), factor)   // already mg
            f.sodiumMg = scale(v("307"), factor)         // already mg
            f.fiberG = scale(v("291"), factor)
            f.totalSugarsG = scale(v("269"), factor)
            f.addedSugarsG = scale(v("539"), factor)
            f.vitaminDMcg = scale(v("328"), factor)      // mcg
            f.calciumMg = scale(v("301"), factor)
            f.ironMg = scale(v("303"), factor)
            f.potassiumMg = scale(v("306"), factor)

            let brand = (food["brandName"] as? String) ?? (food["brandOwner"] as? String)
            return FoodSearchResult(
                id: "usda:\((food["fdcId"] as? Int).map(String.init) ?? desc)",
                name: Food.normalizedName(desc),
                brand: brand.flatMap { $0.isEmpty ? nil : Food.normalizedName($0) },
                source: "USDA", facts: f
            )
        }
    }

    // MARK: - Helpers

    private static func fetchJSON(_ request: URLRequest) async -> Any? {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }

    /// Read a JSON number that APIs sometimes deliver as a String.
    private static func num(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    /// Scale an optional per-100g value to a serving; nil stays nil (so the
    /// field is left for the user rather than zeroed).
    private static func scale(_ value: Double?, _ factor: Double) -> Double? {
        value.map { ($0 * factor * 100).rounded() / 100 }
    }

    /// Trim a gram count to a clean label ("30" not "30.0").
    private static func trim(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

import Foundation

/// One candidate from an online food-database lookup — a name, where it came
/// from, and the structured nutrition it would prefill. The user still picks
/// one and confirms every field in the form before it becomes a `Food`, so
/// these are explicitly approximate.
struct FoodSearchResult: Identifiable, Sendable {
    let id: String
    let name: String
    let brand: String?
    /// Which database this came from, shown so approximate numbers read as such.
    let source: String
    /// Nutrition mapped onto the form (scaled to the serving below when known).
    let facts: NutritionFacts

    var calories: Double? { facts.calories }

    /// Secondary line for the list: brand · serving · source.
    var detail: String {
        var parts: [String] = []
        if let brand, !brand.isEmpty { parts.append(brand) }
        if let s = facts.servingDesc, !s.isEmpty { parts.append(s) }
        parts.append(source)
        return parts.joined(separator: " · ")
    }
}

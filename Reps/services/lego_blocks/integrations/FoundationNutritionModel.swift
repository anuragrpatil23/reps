import Foundation
import FoundationModels

/// Structured extraction of nutrition facts from OCR text using Apple's
/// on-device Foundation model (iOS 26+). Guided generation returns typed fields
/// directly — far more robust than regex against messy label layouts.
@available(iOS 26.0, *)
enum FoundationNutritionModel {
    @Generable
    struct Extracted {
        @Guide(description: "The product / food name — the brand or item, e.g. 'Cheerios' or 'Peanut Butter'. This is printed on the packaging above or beside the panel, NOT inside the Nutrition Facts box itself (which only lists nutrients). Pick the most prominent non-nutrient text; omit if none is present.")
        var name: String?
        @Guide(description: "Serving size text, e.g. '1 cup (170g)' or '3 crackers'")
        var servingDesc: String?
        @Guide(description: "Number of pieces/items in one serving, e.g. 3 for '3 crackers'. Omit for measured servings like cups or grams.")
        var servingPieces: Double?
        @Guide(description: "Calories (kcal) per serving — the large headline number by the word 'Calories'. In OCR text it often appears on the line directly below the 'Calories' label rather than next to it. Ignore any 'Calories from fat' value.")
        var calories: Double?
        @Guide(description: "Protein grams per serving")
        var proteinG: Double?
        @Guide(description: "Total carbohydrate grams per serving")
        var carbsG: Double?
        @Guide(description: "Total fat grams per serving")
        var fatG: Double?
        @Guide(description: "Saturated fat grams per serving")
        var satFatG: Double?
        @Guide(description: "Trans fat grams per serving")
        var transFatG: Double?
        @Guide(description: "Cholesterol milligrams per serving")
        var cholesterolMg: Double?
        @Guide(description: "Sodium milligrams per serving")
        var sodiumMg: Double?
        @Guide(description: "Dietary fiber grams per serving")
        var fiberG: Double?
        @Guide(description: "Total sugars grams per serving")
        var totalSugarsG: Double?
        @Guide(description: "Added sugars grams per serving")
        var addedSugarsG: Double?
        @Guide(description: "Vitamin D micrograms per serving")
        var vitaminDMcg: Double?
        @Guide(description: "Calcium milligrams per serving")
        var calciumMg: Double?
        @Guide(description: "Iron milligrams per serving")
        var ironMg: Double?
        @Guide(description: "Potassium milligrams per serving")
        var potassiumMg: Double?
    }

    static func extract(from lines: [String]) async -> NutritionFacts? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(
            instructions: "You extract nutrition facts from the raw OCR text of a food package. Report values per serving. The product name is packaging text near the top or side — never inside the Nutrition Facts panel — so read it from the surrounding lines. Omit any field you cannot find."
        )
        let prompt = "Nutrition label text:\n" + lines.joined(separator: "\n")
        do {
            let response = try await session.respond(to: prompt, generating: Extracted.self)
            let e = response.content
            return NutritionFacts(
                name: e.name, servingDesc: e.servingDesc,
                servingPieces: e.servingPieces,
                calories: e.calories, proteinG: e.proteinG,
                carbsG: e.carbsG, fatG: e.fatG,
                satFatG: e.satFatG, transFatG: e.transFatG,
                cholesterolMg: e.cholesterolMg, sodiumMg: e.sodiumMg,
                fiberG: e.fiberG, totalSugarsG: e.totalSugarsG,
                addedSugarsG: e.addedSugarsG, vitaminDMcg: e.vitaminDMcg,
                calciumMg: e.calciumMg, ironMg: e.ironMg, potassiumMg: e.potassiumMg
            )
        } catch {
            return nil
        }
    }
}

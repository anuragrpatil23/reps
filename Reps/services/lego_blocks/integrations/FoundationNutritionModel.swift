import Foundation
import FoundationModels

/// Structured extraction of nutrition facts from OCR text using Apple's
/// on-device Foundation model (iOS 26+). Guided generation returns typed fields
/// directly — far more robust than regex against messy label layouts.
@available(iOS 26.0, *)
enum FoundationNutritionModel {
    @Generable
    struct Extracted {
        @Guide(description: "Product or food name, if present on the label")
        var name: String?
        @Guide(description: "Serving size text, e.g. '1 cup (170g)'")
        var servingDesc: String?
        @Guide(description: "Calories (kcal) per serving")
        var calories: Double?
        @Guide(description: "Protein grams per serving")
        var proteinG: Double?
        @Guide(description: "Total carbohydrate grams per serving")
        var carbsG: Double?
        @Guide(description: "Total fat grams per serving")
        var fatG: Double?
        @Guide(description: "Servings per container, if stated")
        var servingsPerContainer: Double?
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
            instructions: "You extract nutrition facts from the raw OCR text of a food label. Report values per serving. Omit any field you cannot find."
        )
        let prompt = "Nutrition label text:\n" + lines.joined(separator: "\n")
        do {
            let response = try await session.respond(to: prompt, generating: Extracted.self)
            let e = response.content
            return NutritionFacts(
                name: e.name, servingDesc: e.servingDesc,
                servingsPerContainer: e.servingsPerContainer,
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

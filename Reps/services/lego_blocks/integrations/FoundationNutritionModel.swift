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
                calories: e.calories, proteinG: e.proteinG,
                carbsG: e.carbsG, fatG: e.fatG
            )
        } catch {
            return nil
        }
    }
}

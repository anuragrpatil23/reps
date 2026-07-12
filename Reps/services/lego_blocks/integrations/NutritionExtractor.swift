import UIKit

/// Turns a nutrition-label photo into structured facts: OCR (Vision) →
/// extraction. Prefers Apple's on-device Foundation Models when available
/// (iOS 26+), falling back to the heuristic parser. Fully on-device either way.
enum NutritionExtractor {
    static func extract(from image: UIImage) async -> NutritionFacts {
        let lines = await TextRecognizer.recognize(image)
        guard !lines.isEmpty else { return NutritionFacts() }

        // The heuristic is deterministic and reads every panel row (including the
        // name guess); the model is stronger on messy layouts but occasionally
        // drops a field. Prefer the model, but backfill its gaps from heuristics
        // so no single miss (e.g. calories) zeroes an otherwise-good scan.
        let heuristic = NutritionLabelParser.parse(lines)
        if #available(iOS 26.0, *), let modelResult = await FoundationNutritionModel.extract(from: lines) {
            return modelResult.filling(from: heuristic)
        }
        return heuristic
    }
}

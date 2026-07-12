import UIKit

/// Turns a nutrition-label photo into structured facts: OCR (Vision) →
/// extraction. Prefers Apple's on-device Foundation Models when available
/// (iOS 26+), falling back to the heuristic parser. Fully on-device either way.
enum NutritionExtractor {
    static func extract(from image: UIImage) async -> NutritionFacts {
        let lines = await TextRecognizer.recognize(image)
        guard !lines.isEmpty else { return NutritionFacts() }

        if #available(iOS 26.0, *), let modelResult = await FoundationNutritionModel.extract(from: lines) {
            return modelResult
        }
        return NutritionLabelParser.parse(lines)
    }
}

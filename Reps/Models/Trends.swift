import Foundation

/// A single point in a metric time series (Visualize tab).
struct MetricPoint: Identifiable, Sendable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Trained-days in one ISO week.
struct WeekBar: Identifiable, Sendable {
    let weekStart: Date
    let count: Int
    var id: Date { weekStart }
}

enum BodyMetricKind: String, CaseIterable, Identifiable, Sendable {
    case weight, bodyFat, bmi, leanMass
    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: "Weight"
        case .bodyFat: "Body fat"
        case .bmi: "BMI"
        case .leanMass: "Lean mass"
        }
    }

    var unit: String {
        switch self {
        case .weight, .leanMass: "lbs"
        case .bodyFat: "%"
        case .bmi: ""
        }
    }

    /// Decimal places for value labels.
    var precision: Int { self == .bmi ? 1 : 1 }
}

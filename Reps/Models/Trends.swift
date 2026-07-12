import Foundation

/// Anything plotted against time — lets range-filtering stay generic.
protocol Dated {
    var date: Date { get }
}

/// A single point in a metric time series (Visualize tab).
struct MetricPoint: Identifiable, Sendable, Dated {
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

/// One weigh-in split into its mass components. `leanLbs + fatLbs == weight`.
struct CompositionPoint: Identifiable, Sendable, Dated {
    let date: Date
    let leanLbs: Double
    let fatLbs: Double
    let bodyFatPct: Double
    var weightLbs: Double { leanLbs + fatLbs }
    var id: Date { date }
}

/// Evenly thin a series down to `max` points (keeps first and last) so bar
/// charts stay readable over long ranges.
func downsample<T>(_ items: [T], to max: Int) -> [T] {
    guard items.count > max, max > 1 else { return items }
    let step = Double(items.count - 1) / Double(max - 1)
    let indices = (0..<max).map { Int((Double($0) * step).rounded()) }
    var seen = Set<Int>()
    return indices.filter { seen.insert($0).inserted }.map { items[$0] }
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

import Foundation
import HealthKit

/// Apple Health daily series for the Trends tab, loaded on demand for the
/// selected range so we never store thousands of activity files in the vault.
@MainActor
@Observable
final class HealthTrends {
    var steps: [MetricPoint] = []
    var activeEnergy: [MetricPoint] = []
    var exercise: [MetricPoint] = []
    var restingHR: [MetricPoint] = []
    private(set) var loadedDays = 0

    /// Health series are capped even for the "All" range — two years is plenty
    /// of daily points and keeps the queries fast.
    func load(days: Int) async {
        guard HealthKitService.isAvailable else { return }
        let window = min(days, 730)
        async let s = HealthKitService.dailySeries(.stepCount, unit: .count(), days: window, options: .cumulativeSum)
        async let e = HealthKitService.dailySeries(.activeEnergyBurned, unit: .kilocalorie(), days: window, options: .cumulativeSum)
        async let x = HealthKitService.dailySeries(.appleExerciseTime, unit: .minute(), days: window, options: .cumulativeSum)
        async let hr = HealthKitService.dailySeries(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), days: window, options: .discreteAverage)
        steps = await s
        activeEnergy = await e
        exercise = await x
        restingHR = await hr
        loadedDays = window
    }
}

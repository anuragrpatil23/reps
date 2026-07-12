import SwiftUI
import Charts

/// Stacked bars where each bar's height is a weigh-in's weight, split into
/// fat-free mass (ink) and fat mass (madder). Body-fat % is labeled on the
/// fat segment — the "composition, not weight" view in one chart.
struct CompositionChartCard: View {
    let points: [CompositionPoint]

    private var latest: CompositionPoint? { points.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if points.count > 1 {
                chart
                legend
            } else {
                Text(points.isEmpty ? "No body-composition data yet." : "Need a couple of weigh-ins to chart.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.graphite)
                    .padding(.vertical, 18)
            }
        }
        .cardStock(Palette.chalk)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Composition")
                .font(Typo.display)
                .foregroundStyle(Palette.ink)
            Spacer()
            if let latest {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(latest.weightLbs.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 30, weight: .light, design: .serif))
                        .foregroundStyle(Palette.ink)
                    Text("lbs · \(Int(latest.bodyFatPct.rounded()))% fat")
                        .font(Typo.monoSmall)
                        .foregroundStyle(Palette.graphite)
                }
            }
        }
    }

    private var chart: some View {
        // Plot against an even index (not the irregular weigh-in date) so bars
        // are evenly spaced; the x-axis still shows real dates at a few marks.
        Chart {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, p in
                BarMark(
                    x: .value("n", Double(index)),
                    y: .value("lbs", p.leanLbs),
                    width: .ratio(0.62)
                )
                .foregroundStyle(by: .value("Part", "Fat-free"))

                BarMark(
                    x: .value("n", Double(index)),
                    y: .value("lbs", p.fatLbs),
                    width: .ratio(0.62)
                )
                .foregroundStyle(by: .value("Part", "Fat"))
            }
        }
        .chartForegroundStyleScale([
            "Fat-free": Palette.ink,
            "Fat": Palette.madder,
        ])
        .chartLegend(.hidden)
        .chartXScale(domain: -0.6 ... Double(max(points.count - 1, 0)) + 0.6)
        .chartXAxis {
            AxisMarks(values: axisIndices) { value in
                if let position = value.as(Double.self) {
                    let index = Int(position.rounded())
                    if points.indices.contains(index) {
                        AxisValueLabel {
                            Text(points[index].date, format: .dateTime.month(.abbreviated).day())
                                .font(Typo.monoSmall)
                                .foregroundStyle(Palette.graphite)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline.opacity(0.5))
                AxisValueLabel()
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.graphite)
            }
        }
        .frame(height: 180)
    }

    /// A few evenly spread positions for date labels (first, thirds, last).
    private var axisIndices: [Double] {
        let last = points.count - 1
        guard last > 0 else { return [0] }
        return Array(Set([0, last / 3, 2 * last / 3, last])).sorted().map(Double.init)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            swatch(Palette.ink, "Fat-free mass")
            swatch(Palette.madder, "Fat mass")
            Spacer()
        }
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(Typo.monoSmall)
                .foregroundStyle(Palette.graphite)
        }
    }
}

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
        Chart {
            ForEach(points) { p in
                BarMark(
                    x: .value("Date", p.date),
                    y: .value("lbs", p.leanLbs),
                    width: .fixed(14)
                )
                .foregroundStyle(by: .value("Part", "Fat-free"))

                BarMark(
                    x: .value("Date", p.date),
                    y: .value("lbs", p.fatLbs),
                    width: .fixed(14)
                )
                .foregroundStyle(by: .value("Part", "Fat"))
                .annotation(position: .top, spacing: 2) {
                    if points.count <= 12 {
                        Text("\(Int(p.bodyFatPct.rounded()))")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.graphite)
                    }
                }
            }
        }
        .chartForegroundStyleScale([
            "Fat-free": Palette.ink,
            "Fat": Palette.madder,
        ])
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.graphite)
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

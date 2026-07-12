import SwiftUI
import Charts

/// One trend card: title, latest value in serif, change over the range, and a
/// calm ink area+line chart. Madder marks only the latest point (and PRs, when
/// `higherIsBetter` flips the semantics). Stays quiet until there's data.
struct MetricChartCard: View {
    let title: String
    let unit: String
    let points: [MetricPoint]
    let stock: Color
    var markPRs = false

    private var latest: MetricPoint? { points.last }

    private var change: Double? {
        guard let first = points.first?.value, let last = points.last?.value,
              points.count > 1 else { return nil }
        return last - first
    }

    private var bounds: (min: Double, max: Double) {
        let values = points.map(\.value)
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.15, 0.5)
        return (lo - pad, hi + pad)
    }

    /// Personal records: each point that exceeds all prior points.
    private var prDates: Set<Date> {
        guard markPRs else { return [] }
        var best = -Double.infinity
        var result: Set<Date> = []
        for p in points where p.value > best {
            best = p.value
            result.insert(p.date)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if points.count > 1 {
                chart
            } else {
                Text(points.isEmpty ? "No data yet." : "One reading so far — need a couple to chart.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.graphite)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            }
        }
        .cardStock(stock)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Typo.display)
                .foregroundStyle(Palette.ink)
            Spacer()
            if let latest {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(latest.value.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 30, weight: .light, design: .serif))
                        .foregroundStyle(Palette.ink)
                    Text(unit)
                        .font(Typo.monoSmall)
                        .foregroundStyle(Palette.graphite)
                }
            }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let change {
                Text("\(change <= 0 ? "▾" : "▴") \(abs(change).formatted(.number.precision(.fractionLength(1)))) \(unit) over \(rangeLabel)")
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.graphite)
            }
            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Min", bounds.min),
                        yEnd: .value("Value", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Palette.ink.opacity(0.14), Palette.ink.opacity(0.01)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                    .foregroundStyle(Palette.ink)
                }
                ForEach(points.filter { prDates.contains($0.date) }) { pr in
                    PointMark(x: .value("Date", pr.date), y: .value("Value", pr.value))
                        .symbolSize(24)
                        .foregroundStyle(Palette.madder)
                }
                if let latest {
                    PointMark(x: .value("Date", latest.date), y: .value("Value", latest.value))
                        .symbolSize(40)
                        .foregroundStyle(Palette.madder)
                }
            }
            .chartYScale(domain: bounds.min...bounds.max)
            .chartXAxis {
                AxisMarks(preset: .aligned, values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(Typo.monoSmall)
                        .foregroundStyle(Palette.graphite)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Palette.hairline.opacity(0.5))
                    AxisValueLabel()
                        .font(Typo.monoSmall)
                        .foregroundStyle(Palette.graphite)
                }
            }
            .frame(height: 150)
        }
    }

    private var rangeLabel: String {
        guard let first = points.first?.date, let last = points.last?.date else { return "range" }
        let days = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
        switch days {
        case ..<45: return "\(days)d"
        case ..<400: return "\(days / 30)mo"
        default: return "\(days / 365)y"
        }
    }
}

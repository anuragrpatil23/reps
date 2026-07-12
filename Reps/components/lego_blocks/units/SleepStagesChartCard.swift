import SwiftUI
import Charts

/// Stacked bars where each bar is one night's sleep, split into stages —
/// deep, core, REM, and awake-in-bed — in hours. The "what kind of sleep, not
/// just how much" view, matching the composition chart's stacked style.
struct SleepStagesChartCard: View {
    let nights: [SleepNight]

    private var latest: SleepNight? { nights.last }

    // Stage → color, in stack order (bottom deep → top awake). A dark-to-light
    // ramp with madder for REM, echoing the Ledger palette.
    private static let stages: [(key: String, label: String, color: Color)] = [
        ("Deep", "Deep", Palette.ink),
        ("Core", "Core", Palette.graphite),
        ("REM", "REM", Palette.madder),
        ("Awake", "Awake", Palette.hairline),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if nights.count > 1 {
                chart
                legend
            } else {
                Text(nights.isEmpty ? "No sleep-stage data yet." : "Need a couple of nights to chart.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.graphite)
                    .padding(.vertical, 18)
            }
        }
        .cardStock(Palette.chalk)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Sleep stages")
                .font(Typo.display)
                .foregroundStyle(Palette.ink)
            Spacer()
            if let latest {
                Text("\(hoursMinutes(latest.asleepH)) asleep")
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.graphite)
            }
        }
    }

    private var chart: some View {
        // Categorical (zero-padded index) x so the stacked bars size their band
        // and render — same trick the composition chart uses. Segments are
        // flattened up front to keep the Chart body simple for the type-checker.
        Chart(bars) { bar in
            BarMark(
                x: .value("night", bar.xKey),
                y: .value("hours", bar.hours),
                width: .ratio(0.7)
            )
            .foregroundStyle(by: .value("Stage", bar.stage))
        }
        .chartForegroundStyleScale(styleScale)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: axisKeys) { value in
                if let key = value.as(String.self), let index = Int(key),
                   nights.indices.contains(index) {
                    AxisValueLabel {
                        Text(nights[index].date, format: .dateTime.month(.abbreviated).day())
                            .font(Typo.monoSmall)
                            .foregroundStyle(Palette.graphite)
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

    /// One stacked segment (a stage's hours for one night).
    private struct StageBar: Identifiable {
        let id = UUID()
        let xKey: String
        let stage: String
        let hours: Double
    }

    /// All non-zero stage segments across every night, flattened for the chart.
    private var bars: [StageBar] {
        nights.enumerated().flatMap { index, night -> [StageBar] in
            let values: [(String, Double)] = [
                ("Deep", night.deepH), ("Core", night.coreH),
                ("REM", night.remH), ("Awake", night.awakeH),
            ]
            return values.compactMap { stage, hours in
                hours > 0 ? StageBar(xKey: key(index), stage: stage, hours: hours) : nil
            }
        }
    }

    private var styleScale: KeyValuePairs<String, Color> {
        ["Deep": Palette.ink, "Core": Palette.graphite, "REM": Palette.madder, "Awake": Palette.hairline]
    }

    private func key(_ index: Int) -> String { String(format: "%03d", index) }

    private var axisKeys: [String] {
        let last = nights.count - 1
        guard last > 0 else { return [key(0)] }
        return Array(Set([0, last / 3, 2 * last / 3, last])).sorted().map(key)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(Self.stages, id: \.key) { stage in
                swatch(stage.color, stage.label)
            }
            Spacer()
        }
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(Typo.monoSmall).foregroundStyle(Palette.graphite)
        }
    }

    private func hoursMinutes(_ hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        return total >= 60 ? "\(total / 60)h \(total % 60)m" : "\(total)m"
    }
}

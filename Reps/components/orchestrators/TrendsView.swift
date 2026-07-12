import SwiftUI
import Charts

/// The Visualize tab — historical body composition, strength progression, and
/// training consistency, in the Ledger aesthetic.
struct TrendsView: View {
    @Environment(LogStore.self) private var store
    @State private var range: TrendRange = .threeMonths
    @State private var selectedLift: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                masthead
                rangePicker
                MetricChartCard(
                    title: "Weight", unit: "lbs",
                    points: ranged(store.metricSeries(.weight)), stock: Palette.chalk
                )
                CompositionChartCard(points: downsample(ranged(store.compositionSeries()), to: 12))
                MetricChartCard(
                    title: "Body fat", unit: "%",
                    points: ranged(store.metricSeries(.bodyFat)), stock: Palette.sage
                )
                MetricChartCard(
                    title: "Lean mass", unit: "lbs",
                    points: ranged(store.metricSeries(.leanMass)), stock: Palette.sage
                )
                strengthCard
                trainingCard
                healthSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.paper.ignoresSafeArea())
        .task { if !store.loaded { store.load() } }
    }

    // MARK: Apple Health (read from activity.csv)

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("FROM APPLE HEALTH")
                .font(Typo.eyebrow)
                .tracking(2.2)
                .foregroundStyle(Palette.graphite)
                .padding(.top, 8)
            MetricChartCard(title: "Sleep", unit: "hr",
                            points: ranged(store.sleepHoursSeries()), stock: Palette.chalk)
            MetricChartCard(title: "Steps", unit: "",
                            points: ranged(store.activitySeries(.steps)), stock: Palette.sage)
            MetricChartCard(title: "Active energy", unit: "kcal",
                            points: ranged(store.activitySeries(.activeEnergy)), stock: Palette.sage)
            MetricChartCard(title: "Exercise", unit: "min",
                            points: ranged(store.activitySeries(.exercise)), stock: Palette.sage)
            MetricChartCard(title: "Resting heart rate", unit: "bpm",
                            points: ranged(store.activitySeries(.restingHR)), stock: Palette.chalk)
            MetricChartCard(title: "Heart rate variability", unit: "ms",
                            points: ranged(store.heartSeries("hrv_sdnn")), stock: Palette.chalk)
            MetricChartCard(title: "Blood oxygen", unit: "%",
                            points: ranged(store.respiratorySeries("spo2_avg")), stock: Palette.sage)
            MetricChartCard(title: "VO₂ max", unit: "",
                            points: ranged(store.heartSeries("vo2max")), stock: Palette.sage)
        }
    }

    private var masthead: some View {
        Text("TRENDS")
            .font(Typo.eyebrow)
            .tracking(2.2)
            .foregroundStyle(Palette.graphite)
    }

    private var rangePicker: some View {
        HStack(spacing: 8) {
            ForEach(TrendRange.allCases) { option in
                let selected = option == range
                Button {
                    range = option
                } label: {
                    Text(option.label)
                        .font(Typo.label)
                        .foregroundStyle(selected ? Palette.paper : Palette.graphite)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            selected ? Palette.ink : Palette.chalk,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: strength

    @ViewBuilder
    private var strengthCard: some View {
        let lifts = store.loggedLiftNames()
        if lifts.isEmpty {
            MetricChartCard(title: "Strength", unit: "lbs", points: [], stock: Palette.chalk)
        } else {
            let lift = selectedLift ?? lifts.first!
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Strength")
                        .font(Typo.display)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Menu {
                        ForEach(lifts, id: \.self) { name in
                            Button(name) { selectedLift = name }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(lift).font(Typo.label)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
                        }
                        .foregroundStyle(Palette.madder)
                    }
                }
                MetricChartCard(
                    title: "Top set", unit: "lbs",
                    points: ranged(store.strengthSeries(lift: lift)),
                    stock: .clear, markPRs: true
                )
                .padding(-18)   // unwrap the inner card's padding; header is above
            }
            .cardStock(Palette.chalk)
        }
    }

    // MARK: training frequency

    private var trainingCard: some View {
        let bars = store.weeklyTrainingCounts(weeks: range.weeks)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Training")
                    .font(Typo.display)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(bars.reduce(0) { $0 + $1.count }) sessions")
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.graphite)
            }
            if bars.allSatisfy({ $0.count == 0 }) {
                Text("No workouts logged yet.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.graphite)
                    .padding(.vertical, 12)
            } else {
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Week", bar.weekStart, unit: .weekOfYear),
                        y: .value("Sessions", bar.count),
                        width: .ratio(0.6)
                    )
                    .cornerRadius(2)
                    .foregroundStyle(Palette.ink)
                }
                .chartYScale(domain: 0...max(4, (bars.map(\.count).max() ?? 0)))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
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
                .frame(height: 130)
            }
        }
        .cardStock(Palette.chalk)
    }

    // MARK: helpers

    private func ranged<T: Dated>(_ points: [T]) -> [T] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -range.days, to: .now)
        else { return points }
        return points.filter { $0.date >= cutoff }
    }
}

enum TrendRange: String, CaseIterable, Identifiable {
    case month, threeMonths, year, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .month: "1M"
        case .threeMonths: "3M"
        case .year: "1Y"
        case .all: "All"
        }
    }

    var days: Int {
        switch self {
        case .month: 31
        case .threeMonths: 92
        case .year: 366
        case .all: 100_000
        }
    }

    var weeks: Int {
        switch self {
        case .month: 6
        case .threeMonths: 13
        case .year: 52
        case .all: 52
        }
    }
}

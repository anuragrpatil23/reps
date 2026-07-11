import SwiftUI

/// The day page — the whole app in one calm ledger sheet.
struct TodayView: View {
    @State private var selectedDay: Date = MockData.day(0)

    private var log: DailyLog? { MockData.log(for: selectedDay) }
    private var spineDays: [Date] { MockData.logs.map(\.date).reversed() }
    private var spineMarks: [DayMark] { MockData.logs.reversed().map { DayMark(log: $0) } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    masthead
                    weightBlock
                    if let activity = log?.activity {
                        ActivityLineView(activity: activity)
                    }
                    if let workout = log?.workout {
                        WorkoutCardView(workout: workout)
                    }
                    foodSection
                    picsSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            SpineView(days: spineDays, marks: spineMarks, selected: $selectedDay)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        .background(Palette.paper.ignoresSafeArea())
        .animation(.easeOut(duration: 0.18), value: selectedDay)
    }

    // MARK: masthead

    private var masthead: some View {
        Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day())
            .uppercased())
            .font(Typo.eyebrow)
            .tracking(2.2)
            .foregroundStyle(Palette.graphite)
    }

    // MARK: weight

    @ViewBuilder
    private var weightBlock: some View {
        if let weight = log?.metrics?.weightLbs {
            VStack(alignment: .leading, spacing: 2) {
                Text(weight.formatted(.number.precision(.fractionLength(1))))
                    .font(Typo.numeral)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: weight))
                HStack(spacing: 10) {
                    Text("lbs")
                        .font(Typo.mono)
                        .foregroundStyle(Palette.graphite)
                    if let delta = MockData.weeklyDelta(for: selectedDay) {
                        Text("\(delta <= 0 ? "▾" : "▴") \(abs(delta).formatted(.number.precision(.fractionLength(1)))) this week")
                            .font(Typo.mono)
                            .foregroundStyle(Palette.graphite)
                    }
                }
            }
        } else {
            Text("No weigh-in")
                .font(Typo.display)
                .foregroundStyle(Palette.graphite)
        }
    }

    // MARK: food

    private var foodSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Food")
            if let food = log?.food, !food.isEmpty {
                ForEach(food) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(entry.at)
                            .font(Typo.mono)
                            .foregroundStyle(Palette.graphite)
                        Text(entry.text ?? entry.recipe ?? "photo")
                            .font(Typo.body)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Palette.hairline).frame(height: 0.5)
                    }
                }
            } else {
                emptyLine("Nothing logged yet.")
            }
        }
    }

    // MARK: pics

    private var picsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Pics")
            HStack(spacing: 12) {
                if let pics = log?.pics, !pics.isEmpty {
                    ForEach(pics) { pic in
                        picThumb(pose: pic.pose)
                    }
                }
                Button {
                    // camera flow lands with the vault store
                } label: {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: 64, height: 84)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Palette.madder)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take progress photo")
            }
        }
    }

    private func picThumb(pose: PicPose) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Palette.chalk)
            .frame(width: 64, height: 84)
            .overlay(alignment: .bottom) {
                Text(pose.rawValue)
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.graphite)
                    .padding(.bottom, 6)
            }
    }

    // MARK: shared bits

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Typo.display)
            .foregroundStyle(Palette.ink)
            .padding(.bottom, 6)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(Typo.body)
            .foregroundStyle(Palette.graphite)
            .padding(.vertical, 9)
    }
}

#Preview {
    TodayView()
}

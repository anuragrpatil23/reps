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
                VStack(alignment: .leading, spacing: 20) {
                    masthead
                    weightBlock
                        .padding(.bottom, 4)
                    if let activity = log?.activity {
                        ActivityLineView(activity: activity)
                            .cardStock(Palette.sage)
                    }
                    if let workout = log?.workout {
                        WorkoutCardView(workout: workout)
                    }
                    foodSection
                        .cardStock(Palette.butter)
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
                ForEach(Array(food.enumerated()), id: \.element.id) { index, entry in
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
                        if index < food.count - 1 {
                            Rectangle().fill(Palette.hairline).frame(height: 0.5)
                        }
                    }
                }
            } else {
                emptyLine("Nothing logged yet.")
            }
        }
    }

    // MARK: pics

    private var picsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Pics")
            HStack(alignment: .top, spacing: 16) {
                if let pics = log?.pics, !pics.isEmpty {
                    ForEach(Array(pics.enumerated()), id: \.element.id) { index, pic in
                        polaroid(pose: pic.pose, tilt: index.isMultiple(of: 2) ? -2.5 : 2)
                    }
                }
                Button {
                    // camera flow lands with the vault store
                } label: {
                    polaroidFrame(tilt: (log?.pics.isEmpty ?? true) ? -1.5 : 1.5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Palette.chalk)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Palette.madder)
                            }
                    } caption: {
                        Text("new")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take progress photo")
            }
            .padding(.vertical, 6)
        }
    }

    private func polaroid(pose: PicPose, tilt: Double) -> some View {
        polaroidFrame(tilt: tilt) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [Palette.chalk, Palette.graphite.opacity(0.25)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        } caption: {
            Text(pose.rawValue)
        }
    }

    /// White polaroid frame: photo window + handwritten caption strip.
    private func polaroidFrame(
        tilt: Double,
        @ViewBuilder photo: () -> some View,
        @ViewBuilder caption: () -> some View
    ) -> some View {
        VStack(spacing: 5) {
            photo()
                .frame(width: 74, height: 88)
            caption()
                .font(Typo.handwriting)
                .foregroundStyle(Palette.graphite)
                .frame(height: 14)
        }
        .padding(6)
        .background(Palette.polaroid, in: RoundedRectangle(cornerRadius: 3))
        .shadow(color: Palette.ink.opacity(0.12), radius: 7, y: 3)
        .rotationEffect(.degrees(tilt))
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

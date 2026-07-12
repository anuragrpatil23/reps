import SwiftUI

/// The signature element: a ledger-edge / measuring-tape strip of day ticks.
/// Ink density IS the consistency record. Scrub or tap to flip day pages.
struct SpineView: View {
    let days: [Date]          // oldest → newest
    let marks: [DayBar]       // parallel to days
    @Binding var selected: Date

    /// Minutes that fill the bar to full height — the volume ceiling.
    private let capMinutes: Double = 75
    private let maxBarHeight: CGFloat = 32

    private let tickWidth: CGFloat = 3
    private let spacing: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let visible = maxVisible(in: geo.size.width)
            let window = Array(zip(days, marks).suffix(visible))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(window, id: \.0) { date, mark in
                    tick(for: date, mark: mark)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .contentShape(Rectangle())
            .gesture(scrub(windowDays: window.map(\.0), width: geo.size.width))
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day picker")
        .accessibilityValue(selected.formatted(date: .abbreviated, time: .omitted))
    }

    private func maxVisible(in width: CGFloat) -> Int {
        max(7, Int(width / (tickWidth + spacing)))
    }

    @ViewBuilder
    private func tick(for date: Date, mark: DayBar) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selected)
        Group {
            if mark.isTrainingless {
                // No movement: a faint tick — a hair taller when something was logged.
                Capsule()
                    .fill(mark.logged ? Palette.graphite : Palette.hairline)
                    .frame(width: tickWidth, height: mark.logged ? 7 : 5)
            } else {
                let total = mark.strengthMin + mark.walkMin
                let barHeight = max(4, maxBarHeight * CGFloat(min(total, capMinutes) / capMinutes))
                let strengthHeight = barHeight * CGFloat(mark.strengthMin / total)
                VStack(spacing: 0) {
                    segment(mark.walkMin, height: barHeight - strengthHeight, color: Palette.moss)
                    segment(mark.strengthMin, height: strengthHeight, color: Palette.ink)
                }
                .frame(width: tickWidth)
                .clipShape(Capsule())
            }
        }
        .frame(maxHeight: 34, alignment: .bottom)
        .overlay(alignment: .bottom) {
            // Madder dot marks the selected day; today always carries the accent.
            if isSelected || isToday {
                Circle()
                    .fill(isToday ? Palette.madder : Palette.ink)
                    .frame(width: 4, height: 4)
                    .offset(y: 9)
            }
        }
    }

    /// One color band of the stacked bar; collapses to nothing when its
    /// minutes are zero, but keeps a visible sliver when present.
    @ViewBuilder
    private func segment(_ minutes: Double, height: CGFloat, color: Color) -> some View {
        if minutes > 0 {
            Rectangle().fill(color).frame(height: max(2, height))
        }
    }

    private func scrub(windowDays: [Date], width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !windowDays.isEmpty else { return }
                let step = tickWidth + spacing
                let usedWidth = step * CGFloat(windowDays.count)
                let origin = width - usedWidth   // window is right-aligned
                let index = Int(((value.location.x - origin) / step).rounded(.down))
                let clamped = min(max(index, 0), windowDays.count - 1)
                if !Calendar.current.isDate(windowDays[clamped], inSameDayAs: selected) {
                    selected = windowDays[clamped]
                }
            }
    }
}

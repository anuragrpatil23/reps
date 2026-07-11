import SwiftUI

/// The signature element: a ledger-edge / measuring-tape strip of day ticks.
/// Ink density IS the consistency record. Scrub or tap to flip day pages.
struct SpineView: View {
    let days: [Date]          // oldest → newest
    let marks: [DayMark]      // parallel to days
    @Binding var selected: Date

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
    private func tick(for date: Date, mark: DayMark) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selected)
        let height: CGFloat = switch mark {
        case .trained: 30
        case .logged: 18
        case .empty: 5
        }
        Capsule()
            .fill(isToday ? Palette.madder : (mark == .empty ? Palette.hairline : Palette.ink))
            .frame(width: tickWidth, height: height)
            .frame(maxHeight: 34, alignment: .bottom)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Circle()
                        .fill(isToday ? Palette.madder : Palette.ink)
                        .frame(width: 4, height: 4)
                        .offset(y: 9)
                }
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

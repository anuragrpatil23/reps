import SwiftUI

/// One quiet line of activity — hairline arcs, not Apple's thick rings.
struct ActivityLineView: View {
    let activity: ActivitySummary

    var body: some View {
        HStack(spacing: 18) {
            metric("Move", value: "\(activity.moveKcal)", progress: ratio(activity.moveKcal, activity.moveGoalKcal))
            metric("Exercise", value: "\(activity.exerciseMin)m", progress: ratio(activity.exerciseMin, activity.exerciseGoalMin))
            metric("Stand", value: "\(activity.standHours)", progress: ratio(activity.standHours, activity.standGoalHours))
            Spacer(minLength: 0)
        }
    }

    private func ratio(_ value: Int, _ goal: Int) -> Double {
        goal > 0 ? min(Double(value) / Double(goal), 1) : 0
    }

    private func metric(_ label: String, value: String, progress: Double) -> some View {
        HStack(spacing: 7) {
            HairlineArc(progress: progress)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(Typo.mono)
                    .foregroundStyle(Palette.ink)
                Text(label)
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.graphite)
            }
        }
    }
}

/// Thin arc: hairline track, ink progress; fills solid only when closed.
struct HairlineArc: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.hairline, lineWidth: 1)
            if progress >= 1 {
                Circle()
                    .stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.5))
            } else {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

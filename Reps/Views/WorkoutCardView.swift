import SwiftUI

/// Prefilled workout card — sticky defaults, edit only the deltas.
struct WorkoutCardView: View {
    let workout: WorkoutEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(workout.title ?? workout.template ?? "Workout")
                    .font(Typo.display)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if let minutes = workout.durationMin {
                    Text("\(minutes)m")
                        .font(Typo.mono)
                        .foregroundStyle(Palette.graphite)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(workout.exercises) { exercise in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(exercise.name)
                            .font(Typo.body)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 12)
                        Text(exercise.notation)
                            .font(Typo.mono)
                            .foregroundStyle(Palette.graphite)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            Button {
                // edit-deltas sheet lands next
            } label: {
                Text(workout.status == .done ? "Logged" : "Log it")
                    .font(Typo.label)
                    .foregroundStyle(workout.status == .done ? Palette.graphite : Palette.madder)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(
                                workout.status == .done ? Palette.hairline : Palette.madder.opacity(0.5),
                                lineWidth: 1
                            )
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Palette.chalk, in: RoundedRectangle(cornerRadius: 14))
    }
}

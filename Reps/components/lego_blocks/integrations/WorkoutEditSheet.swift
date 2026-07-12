import SwiftUI

/// Edit-deltas sheet: opens prefilled from sticky defaults; the whole
/// interaction is tweaking a few numbers and hitting Done.
struct WorkoutEditSheet: View {
    @State var draft: WorkoutEntry
    let onSave: (WorkoutEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach($draft.exercises) { $exercise in
                        exerciseEditor($exercise)
                    }
                }
                .padding(20)
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(draft.title ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Palette.graphite)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var final = draft
                        final.status = .done
                        if final.startedAt == nil { final.startedAt = Date() }
                        onSave(final)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.madder)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Mark as rest day") {
                        onSave(WorkoutEntry(status: .rest))
                        dismiss()
                    }
                    .font(Typo.label)
                    .foregroundStyle(Palette.graphite)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editing = false }.foregroundStyle(Palette.madder)
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseEditor(_ exercise: Binding<ExerciseEntry>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise.wrappedValue.name)
                .font(Typo.display)
                .foregroundStyle(Palette.ink)
            if exercise.wrappedValue.sets != nil {
                setsEditor(exercise)
            } else {
                cardioEditor(exercise)
            }
        }
        .flatCard(Palette.chalk)
    }

    private func setsEditor(_ exercise: Binding<ExerciseEntry>) -> some View {
        VStack(spacing: 8) {
            ForEach(Array((exercise.wrappedValue.sets ?? []).indices), id: \.self) { index in
                HStack(spacing: 12) {
                    Text("set \(index + 1)")
                        .font(Typo.monoSmall)
                        .foregroundStyle(Palette.graphite)
                        .frame(width: 44, alignment: .leading)
                    numberField(
                        "reps",
                        value: Binding(
                            get: { Double(exercise.wrappedValue.sets?[index].reps ?? 0) },
                            set: { exercise.wrappedValue.sets?[index].reps = Int($0) }
                        ),
                        integer: true
                    )
                    Text("×")
                        .font(Typo.mono)
                        .foregroundStyle(Palette.graphite)
                    numberField(
                        "lbs",
                        value: Binding(
                            get: { exercise.wrappedValue.sets?[index].weightLbs ?? 0 },
                            set: { exercise.wrappedValue.sets?[index].weightLbs = $0 }
                        ),
                        integer: false
                    )
                    Spacer(minLength: 0)
                }
            }
            HStack {
                Button {
                    let last = exercise.wrappedValue.sets?.last ?? SetEntry(reps: 8, weightLbs: 0)
                    exercise.wrappedValue.sets?.append(last)
                } label: {
                    Label("Add set", systemImage: "plus")
                        .font(Typo.label)
                        .foregroundStyle(Palette.madder)
                }
                Spacer()
                if (exercise.wrappedValue.sets?.count ?? 0) > 1 {
                    Button {
                        exercise.wrappedValue.sets?.removeLast()
                    } label: {
                        Label("Remove set", systemImage: "minus")
                            .font(Typo.label)
                            .foregroundStyle(Palette.graphite)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    private func cardioEditor(_ exercise: Binding<ExerciseEntry>) -> some View {
        HStack(spacing: 12) {
            numberField(
                "min",
                value: Binding(
                    get: { Double(exercise.wrappedValue.durationMin ?? 0) },
                    set: { exercise.wrappedValue.durationMin = Int($0) }
                ),
                integer: true
            )
            numberField(
                "incline %",
                value: Binding(
                    get: { exercise.wrappedValue.inclinePct ?? 0 },
                    set: { exercise.wrappedValue.inclinePct = $0 }
                ),
                integer: false
            )
            numberField(
                "mph",
                value: Binding(
                    get: { exercise.wrappedValue.speedMph ?? 0 },
                    set: { exercise.wrappedValue.speedMph = $0 }
                ),
                integer: false
            )
            Spacer(minLength: 0)
        }
    }

    private func numberField(_ unit: String, value: Binding<Double>, integer: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(
                unit,
                value: value,
                format: integer ? .number.precision(.fractionLength(0)) : .number
            )
            .keyboardType(integer ? .numberPad : .decimalPad)
            .focused($editing)
            .font(Typo.mono)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(width: 78)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
            Text(unit)
                .font(Typo.monoSmall)
                .foregroundStyle(Palette.graphite)
        }
    }
}

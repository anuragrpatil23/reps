import SwiftUI

/// Edit-deltas sheet: opens prefilled from sticky defaults; the whole
/// interaction is tweaking a few numbers and hitting Done.
struct WorkoutEditSheet: View {
    @State var draft: WorkoutEntry
    let onSave: (WorkoutEntry) -> Void
    @Environment(LogStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach($draft.exercises) { $exercise in
                        exerciseEditor($exercise) {
                            draft.exercises.removeAll { $0.id == exercise.id }
                        }
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

    private func exerciseEditor(_ exercise: Binding<ExerciseEntry>, onRemove: @escaping () -> Void) -> some View {
        // Resolve the library entry so the edit sheet carries the same cue and
        // how-to link the day-page card shows — one world, not two.
        let library = store.exercise(exercise.wrappedValue.exerciseId)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.wrappedValue.name)
                    .font(Typo.display)
                    .foregroundStyle(Palette.ink)
                if let link = library?.links.first {
                    Button {
                        if let url = URL(string: link.url) { openURL(url) }
                    } label: {
                        Image(systemName: "play.circle").font(.footnote).foregroundStyle(Palette.madder)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .font(.footnote)
                        .foregroundStyle(Palette.graphite)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove exercise")
            }
            if let cue = library?.cue, !cue.isEmpty {
                Text(cue).font(Typo.monoSmall).foregroundStyle(Palette.graphite)
            }
            if exercise.wrappedValue.sets != nil {
                setsEditor(exercise, library: library)
            } else {
                cardioEditor(exercise)
            }
        }
        .flatCard(Palette.chalk)
    }

    private func setsEditor(_ exercise: Binding<ExerciseEntry>, library: Exercise?) -> some View {
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
                    // Copy the last set, else fall back to the library defaults.
                    let fallback = SetEntry(
                        reps: library?.defaultReps ?? 10,
                        weightLbs: library?.defaultWeight(for: .current) ?? 0
                    )
                    let last = exercise.wrappedValue.sets?.last ?? fallback
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

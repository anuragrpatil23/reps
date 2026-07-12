import SwiftUI

/// The exercise library: your personal list of movements, each with a muscle
/// group, a one-line form cue, and how-to links. Templates pick from here, so
/// names stay consistent and your form videos are one tap away in the workout.
struct ExerciseLibrarySheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editingExercise: Exercise?
    @State private var newExercise = false

    /// Exercises grouped by muscle, in a stable display order (known groups
    /// first, then any custom ones alphabetically).
    private var groups: [(muscle: String, items: [Exercise])] {
        let byMuscle = Dictionary(grouping: store.exercises) { $0.muscle }
        let extras = byMuscle.keys.filter { !ExerciseEditSheet.muscleOrder.contains($0) }.sorted()
        let muscles = ExerciseEditSheet.muscleOrder + extras
        var result: [(muscle: String, items: [Exercise])] = []
        for m in muscles {
            guard let items = byMuscle[m] else { continue }
            result.append((m, items.sorted { $0.name < $1.name }))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                if store.exercises.isEmpty {
                    Text("No exercises yet. Add the movements you train — each can carry a form cue and how-to links.")
                        .font(Typo.body).foregroundStyle(Palette.graphite)
                }
                ForEach(groups, id: \.muscle) { group in
                    Section(group.muscle.capitalized) {
                        ForEach(group.items) { exercise in
                            Button { editingExercise = exercise } label: { row(exercise) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { indexes in
                            indexes.map { group.items[$0] }.forEach { store.deleteExercise($0.key) }
                        }
                    }
                }
                Section {
                    Button { newExercise = true } label: {
                        Label("New exercise", systemImage: "plus").foregroundStyle(Palette.madder)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.madder)
                }
            }
            .sheet(item: $editingExercise) { ExerciseEditSheet(editing: $0) }
            .sheet(isPresented: $newExercise) { ExerciseEditSheet(editing: nil) }
        }
    }

    private func row(_ exercise: Exercise) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(Typo.body).foregroundStyle(Palette.ink)
                if let cue = exercise.cue, !cue.isEmpty {
                    Text(cue).font(Typo.monoSmall).foregroundStyle(Palette.graphite).lineLimit(1)
                }
            }
            Spacer()
            if !exercise.links.isEmpty {
                Image(systemName: "link").font(.footnote).foregroundStyle(Palette.graphite)
            }
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.hairline)
        }
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
    }
}

/// Edit one exercise: name, muscle group, form cue, and how-to links.
struct ExerciseEditSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editing: Exercise?
    /// Called with the saved exercise — lets the template picker add a
    /// just-created exercise straight into the workout.
    var onSaved: ((Exercise) -> Void)? = nil

    static let muscleOrder = ["chest", "back", "legs", "shoulders", "arms", "core", "cardio", "other"]

    @State private var name = ""
    @State private var muscle = "chest"
    @State private var cue = ""
    @State private var links: [ExerciseLink] = []
    @State private var defaultReps = 10.0
    @State private var weightMale = 0.0
    @State private var weightFemale = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name (e.g. Bench press)", text: $name).font(Typo.body)
                    Picker("Muscle", selection: $muscle) {
                        ForEach(Self.muscleOrder, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    TextField("Form cue (optional)", text: $cue).font(Typo.body)
                }

                Section {
                    numberRow("Default reps", value: $defaultReps, integer: true)
                    numberRow("Weight — male", value: $weightMale, unit: "lb")
                    numberRow("Weight — female", value: $weightFemale, unit: "lb")
                } header: {
                    Text("Defaults")
                } footer: {
                    Text("Used to prefill sets when this exercise is added. The weight follows the Sex set in Settings.")
                }

                Section {
                    // Keyed by position, not the link's id — the fields are the
                    // mutable id, so id-keying would drop focus each keystroke.
                    ForEach(links.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Label (e.g. Form)", text: $links[index].label).font(Typo.body)
                            TextField("https://youtu.be/…", text: $links[index].url)
                                .font(Typo.monoSmall).foregroundStyle(Palette.graphite)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }
                    }
                    .onDelete { links.remove(atOffsets: $0) }
                    Button { links.append(ExerciseLink(label: "Form", url: "")) } label: {
                        Label("Add link", systemImage: "plus").foregroundStyle(Palette.madder)
                    }
                } header: {
                    Text("How-to links")
                } footer: {
                    Text("Quick references (YouTube form videos, notes). Tap an exercise in a workout to open its first link.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .environment(\.editMode, .constant(.active))
            .navigationTitle(editing == nil ? "New exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.graphite)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold).foregroundStyle(Palette.madder)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let editing {
                    name = editing.name
                    muscle = editing.muscle
                    cue = editing.cue ?? ""
                    links = editing.links
                    defaultReps = Double(editing.defaultReps)
                    weightMale = editing.defaultWeightMale
                    weightFemale = editing.defaultWeightFemale
                }
            }
        }
    }

    private func numberRow(_ label: String, value: Binding<Double>, unit: String? = nil, integer: Bool = false) -> some View {
        HStack {
            Text(label).font(Typo.body).foregroundStyle(Palette.ink)
            Spacer()
            TextField(label, value: value, format: integer ? .number.precision(.fractionLength(0)) : .number)
                .keyboardType(integer ? .numberPad : .decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Typo.mono).foregroundStyle(Palette.madder)
                .frame(width: 60)
            if let unit { Text(unit).font(Typo.monoSmall).foregroundStyle(Palette.graphite) }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let key = editing?.key ?? store.uniqueExerciseKey(for: trimmed)
        let cleanedLinks = links
            .map { ExerciseLink(label: $0.label.trimmingCharacters(in: .whitespaces),
                                url: $0.url.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.url.isEmpty }
        let exercise = Exercise(
            key: key, name: trimmed, muscle: muscle,
            cue: cue.trimmingCharacters(in: .whitespaces).isEmpty ? nil : cue,
            links: cleanedLinks,
            defaultReps: max(1, Int(defaultReps)),
            defaultWeightMale: max(0, weightMale),
            defaultWeightFemale: max(0, weightFemale)
        )
        store.saveExercise(exercise)
        onSaved?(exercise)
        dismiss()
    }
}

/// Pick an exercise from the library to add to a template — search, tap, or
/// create a new one on the spot (which is added straight in).
struct ExercisePickerSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let onPick: (Exercise) -> Void

    @State private var search = ""
    @State private var newExercise = false

    private var filtered: [Exercise] {
        let all = store.exercises.sorted { $0.name.lowercased() < $1.name.lowercased() }
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { exercise in
                    Button { onPick(exercise); dismiss() } label: {
                        HStack {
                            Text(exercise.name).font(Typo.body).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(exercise.muscle.capitalized)
                                .font(Typo.monoSmall).foregroundStyle(Palette.graphite)
                            if !exercise.links.isEmpty {
                                Image(systemName: "link").font(.footnote).foregroundStyle(Palette.hairline)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.graphite)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { newExercise = true } label: { Label("New", systemImage: "plus") }
                        .foregroundStyle(Palette.madder)
                }
            }
            .sheet(isPresented: $newExercise) {
                ExerciseEditSheet(editing: nil) { created in
                    onPick(created)
                    dismiss()
                }
            }
        }
    }
}

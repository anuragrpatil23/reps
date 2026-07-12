import SwiftUI

/// The training hub: pick the active program, edit programs (phase + rotation +
/// rest days), and manage the workout templates ("pushes") they rotate through.
struct ProgramSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editingProgram: Program?
    @State private var newProgram = false
    @State private var editingTemplate: WorkoutTemplate?
    @State private var newTemplate = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.programs.isEmpty {
                        Text("No programs yet. Create one to schedule your week — an ordered rotation of workouts with fixed rest days.")
                            .font(Typo.body).foregroundStyle(Palette.graphite)
                    }
                    ForEach(store.programs) { program in
                        Button { editingProgram = program } label: { programRow(program) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { $0.map { store.programs[$0] }.forEach { store.deleteProgram($0.key) } }
                    Button { newProgram = true } label: {
                        Label("New program", systemImage: "plus").foregroundStyle(Palette.madder)
                    }
                } header: {
                    Text("Programs")
                } footer: {
                    Text("The active program (checked) drives each day's scheduled workout. The rotation walks across training days, skipping rest days — so with an odd rotation the weekday drifts week to week.")
                }

                Section {
                    ForEach(store.templates) { template in
                        Button { editingTemplate = template } label: { templateRow(template) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { $0.map { store.templates[$0] }.forEach { store.deleteTemplate($0.key) } }
                    Button { newTemplate = true } label: {
                        Label("New workout", systemImage: "plus").foregroundStyle(Palette.madder)
                    }
                } header: {
                    Text("Workouts")
                } footer: {
                    Text("Each workout (push, pull, legs…) is a reusable template. Programs rotate through them.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.madder)
                }
            }
            .sheet(item: $editingProgram) { ProgramEditSheet(editing: $0) }
            .sheet(isPresented: $newProgram) { ProgramEditSheet(editing: nil) }
            .sheet(item: $editingTemplate) { TemplateEditSheet(editing: $0) }
            .sheet(isPresented: $newTemplate) { TemplateEditSheet(editing: nil) }
        }
    }

    private func programRow(_ program: Program) -> some View {
        HStack {
            Image(systemName: store.activeProgramKey == program.key ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(store.activeProgramKey == program.key ? Palette.madder : Palette.hairline)
                .onTapGesture { store.activeProgramKey = program.key }
            VStack(alignment: .leading, spacing: 2) {
                Text(program.title).font(Typo.body).foregroundStyle(Palette.ink)
                Text("\(program.phase.label) · \(program.rotation.count)-workout rotation")
                    .font(Typo.monoSmall).foregroundStyle(Palette.graphite)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.hairline)
        }
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
    }

    private func templateRow(_ template: WorkoutTemplate) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title).font(Typo.body).foregroundStyle(Palette.ink)
                Text(template.exercises.map(\.name).joined(separator: " · "))
                    .font(Typo.monoSmall).foregroundStyle(Palette.graphite).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.hairline)
        }
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
    }
}

/// Edit one program: title, phase, rest days, and the ordered rotation of
/// workouts drawn from the template library.
private struct ProgramEditSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editing: Program?

    @State private var title = ""
    @State private var phase: TrainingPhase = .cut
    @State private var restDays: Set<Weekday> = [.tue, .fri]
    @State private var rotation: [String] = []
    @State private var anchor = Calendar.current.startOfDay(for: .now)
    @State private var addingWorkout = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Program") {
                    TextField("Name (e.g. April Cut)", text: $title).font(Typo.body)
                    Picker("Phase", selection: $phase) {
                        ForEach(TrainingPhase.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    ForEach(Weekday.allCases.sorted()) { day in
                        Toggle(isOn: restBinding(day)) {
                            Text(day.short).font(Typo.body).foregroundStyle(Palette.ink)
                        }
                        .tint(Palette.madder)
                    }
                } header: {
                    Text("Rest days")
                } footer: {
                    Text("\(7 - restDays.count) training days a week.")
                }

                Section {
                    if rotation.isEmpty {
                        Text("Add workouts in the order you rotate through them.")
                            .font(Typo.body).foregroundStyle(Palette.graphite)
                    }
                    ForEach(Array(rotation.enumerated()), id: \.offset) { index, key in
                        HStack {
                            Text("\(index + 1)").font(Typo.mono).foregroundStyle(Palette.graphite)
                                .frame(width: 22, alignment: .leading)
                            Text(store.template(key)?.title ?? key)
                                .font(Typo.body).foregroundStyle(Palette.ink)
                        }
                    }
                    .onMove { rotation.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { rotation.remove(atOffsets: $0) }
                    Button { addingWorkout = true } label: {
                        Label("Add workout to rotation", systemImage: "plus").foregroundStyle(Palette.madder)
                    }
                    .disabled(store.templates.isEmpty)
                } header: {
                    Text("Rotation")
                } footer: {
                    Text("Repeat a workout in the list if it comes up more than once per cycle.")
                }

                Section {
                    DatePicker("Cycle start", selection: $anchor, displayedComponents: .date)
                        .font(Typo.body)
                } footer: {
                    Text("The day the first workout in the rotation is (or was) done. Everything else counts forward from here.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .environment(\.editMode, .constant(.active))
            .navigationTitle(editing == nil ? "New program" : "Edit program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.graphite)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold).foregroundStyle(Palette.madder)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Add workout", isPresented: $addingWorkout, titleVisibility: .visible) {
                ForEach(store.templates) { template in
                    Button(template.title) { rotation.append(template.key) }
                }
            }
            .onAppear { if let editing { populate(editing) } }
        }
    }

    private func restBinding(_ day: Weekday) -> Binding<Bool> {
        Binding(
            get: { restDays.contains(day) },
            set: { on in if on { restDays.insert(day) } else { restDays.remove(day) } }
        )
    }

    private func populate(_ program: Program) {
        title = program.title
        phase = program.phase
        restDays = program.restDays
        rotation = program.rotation
        anchor = program.anchor
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let key = editing?.key ?? store.uniqueProgramKey(for: trimmed)
        store.saveProgram(Program(
            key: key, title: trimmed, phase: phase,
            rotation: rotation, restDays: restDays, anchor: anchor
        ))
        dismiss()
    }
}

/// Edit one workout template: its name and exercises (strength sets or cardio).
private struct TemplateEditSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editing: WorkoutTemplate?

    @State private var title = ""
    @State private var exercises: [ExerciseEntry] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Name (e.g. Push A)", text: $title).font(Typo.body)
                }

                ForEach($exercises) { $exercise in
                    Section {
                        TextField("Exercise name", text: $exercise.name).font(Typo.body)
                        if exercise.sets != nil {
                            setsEditor($exercise)
                        } else {
                            cardioEditor($exercise)
                        }
                    }
                }
                .onDelete { exercises.remove(atOffsets: $0) }

                Section {
                    Button { exercises.append(ExerciseEntry(name: "", sets: [SetEntry(reps: 8, weightLbs: 0)])) } label: {
                        Label("Add strength exercise", systemImage: "plus").foregroundStyle(Palette.madder)
                    }
                    Button { exercises.append(ExerciseEntry(name: "", durationMin: 20)) } label: {
                        Label("Add cardio", systemImage: "plus").foregroundStyle(Palette.madder)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(editing == nil ? "New workout" : "Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.graphite)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold).foregroundStyle(Palette.madder)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if let editing { title = editing.title; exercises = editing.exercises } }
        }
    }

    private func setsEditor(_ exercise: Binding<ExerciseEntry>) -> some View {
        Group {
            ForEach(Array((exercise.wrappedValue.sets ?? []).indices), id: \.self) { index in
                HStack(spacing: 12) {
                    Text("set \(index + 1)").font(Typo.monoSmall).foregroundStyle(Palette.graphite)
                        .frame(width: 44, alignment: .leading)
                    numberField("reps", value: Binding(
                        get: { Double(exercise.wrappedValue.sets?[index].reps ?? 0) },
                        set: { exercise.wrappedValue.sets?[index].reps = Int($0) }), integer: true)
                    Text("×").font(Typo.mono).foregroundStyle(Palette.graphite)
                    numberField("lbs", value: Binding(
                        get: { exercise.wrappedValue.sets?[index].weightLbs ?? 0 },
                        set: { exercise.wrappedValue.sets?[index].weightLbs = $0 }), integer: false)
                    Spacer(minLength: 0)
                }
            }
            HStack {
                Button {
                    let last = exercise.wrappedValue.sets?.last ?? SetEntry(reps: 8, weightLbs: 0)
                    exercise.wrappedValue.sets?.append(last)
                } label: { Label("Add set", systemImage: "plus").font(Typo.label).foregroundStyle(Palette.madder) }
                Spacer()
                if (exercise.wrappedValue.sets?.count ?? 0) > 1 {
                    Button { exercise.wrappedValue.sets?.removeLast() } label: {
                        Label("Remove set", systemImage: "minus").font(Typo.label).foregroundStyle(Palette.graphite)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func cardioEditor(_ exercise: Binding<ExerciseEntry>) -> some View {
        HStack(spacing: 12) {
            numberField("min", value: Binding(
                get: { Double(exercise.wrappedValue.durationMin ?? 0) },
                set: { exercise.wrappedValue.durationMin = Int($0) }), integer: true)
            numberField("incline %", value: Binding(
                get: { exercise.wrappedValue.inclinePct ?? 0 },
                set: { exercise.wrappedValue.inclinePct = $0 }), integer: false)
            numberField("mph", value: Binding(
                get: { exercise.wrappedValue.speedMph ?? 0 },
                set: { exercise.wrappedValue.speedMph = $0 }), integer: false)
            Spacer(minLength: 0)
        }
    }

    private func numberField(_ unit: String, value: Binding<Double>, integer: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(unit, value: value, format: integer ? .number.precision(.fractionLength(0)) : .number)
                .keyboardType(integer ? .numberPad : .decimalPad)
                .font(Typo.mono).foregroundStyle(Palette.ink)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(width: 78)
                .background(Palette.chalk, in: RoundedRectangle(cornerRadius: 8))
            Text(unit).font(Typo.monoSmall).foregroundStyle(Palette.graphite)
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let key = editing?.key ?? store.uniqueTemplateKey(for: trimmed)
        let cleaned = exercises
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        store.saveTemplate(WorkoutTemplate(key: key, title: trimmed, exercises: cleaned))
        dismiss()
    }
}

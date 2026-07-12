import SwiftUI
import PhotosUI

/// The day page — the whole app in one calm ledger sheet.
struct TodayView: View {
    @Environment(LogStore.self) private var store
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var showingWorkoutSheet = false
    @State private var addingWorkoutExercise = false
    @State private var showingFoodSheet = false
    @State private var editingFood: FoodEntry?
    @State private var showingSettings = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingPhoto: Data?
    @State private var showingCamera = false
    @State private var picViewer: ProgressPicContext?
    @State private var picsUnlocked = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    /// Target body-fat %, a personal preference (0 = unset). Shared with Settings.
    @AppStorage("reps.targetBodyFatPct") private var targetBodyFatPct = 0.0

    /// Blur progress pics + require Face ID to open them. Default on. Shared with Settings.
    @AppStorage("reps.lockPhotos") private var lockPhotos = true

    // Energy & macro knobs (edited in Settings). Baseline 0 = auto from lean mass.
    @AppStorage("reps.baselineBurn") private var baselineBurn = 0.0
    @AppStorage("reps.dailyDeficit") private var dailyDeficit = 500.0
    @AppStorage("reps.proteinPerLbLean") private var proteinPerLbLean = 1.0
    @AppStorage("reps.fatPerLbBody") private var fatPerLbBody = 0.35

    /// Today's energy picture from the most-recent weigh-in, today's movement,
    /// and what's logged — the source for the balance + macro-target lines.
    private var budget: EnergyBudget {
        let metrics = log?.metrics ?? store.recentMetrics(asOf: selectedDay)?.metrics
        return EnergyBudget(
            leanMassLbs: metrics?.leanMass,
            weightLbs: metrics?.weightLbs,
            activeKcal: Double(log?.activity?.moveKcal ?? 0),
            intake: store.macros(for: selectedDay),
            baselineOverride: baselineBurn,
            dailyDeficit: dailyDeficit,
            proteinPerLbLean: proteinPerLbLean,
            fatPerLbBody: fatPerLbBody
        )
    }

    private var log: DailyLog? { store.log(for: selectedDay) }

    /// Total minutes of watch-recorded workouts on a day — floors the Exercise
    /// ring so a long session isn't hidden by Apple's stingy minute credit.
    private func sessionMinutes(on date: Date) -> Int {
        Int(store.workoutSessions(on: date).reduce(0) { $0 + $1.durationMin }.rounded())
    }

    /// Rolling window ending today; empty days render as faint dots.
    private var spineDays: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<120).reversed().compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: today)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    masthead
                    weightBlock
                        .padding(.bottom, 4)
                    if let activity = log?.activity {
                        ActivityLineView(activity: activity, sessionMinutes: sessionMinutes(on: selectedDay))
                            .cardStock(Palette.sage)
                    }
                    sleepSection
                    sessionsSection
                    workoutSection
                    foodSection
                        .cardStock(Palette.butter)
                    energySection
                    picsSection
                    DayNotesEditor(
                        day: selectedDay,
                        initialText: log?.note ?? ""
                    ) { note in
                        store.saveNote(note, on: selectedDay)
                    }
                    .id(selectedDay)   // fresh editor per day; commits the one we leave
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable { await store.syncHealth(around: selectedDay) }
            SpineView(
                days: spineDays,
                marks: spineDays.map {
                    DayBar(split: store.trainingSplit(on: $0), log: store.log(for: $0))
                },
                selected: $selectedDay
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .background(Palette.paper.ignoresSafeArea())
        .animation(.easeOut(duration: 0.18), value: selectedDay)
        .task {
            if !store.loaded { store.load() }
            await store.syncHealth(around: selectedDay)
        }
        .sheet(isPresented: $showingWorkoutSheet) {
            WorkoutEditSheet(draft: log?.workout ?? store.stickyWorkout(for: selectedDay)) { final in
                store.saveWorkout(final, on: selectedDay)
            }
        }
        .sheet(isPresented: $showingFoodSheet) {
            FoodPickerSheet { entry in
                store.addFood(entry, on: selectedDay)
            }
        }
        .sheet(isPresented: $addingWorkoutExercise) {
            ExercisePickerSheet { exercise in
                store.logExercise(loggableEntry(for: exercise), on: selectedDay)
            }
        }
        .sheet(item: $editingFood) { entry in
            if let id = entry.foodId, let food = store.food(id) {
                ServingEditor(food: food, editing: entry) { updated in
                    store.updateFood(updated, on: selectedDay)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet()
        }
        .photosPicker(isPresented: photoPickerBinding, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) {
            guard let photoItem else { return }
            Task {
                if let data = try? await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    pendingPhoto = ProgressImage.encode(image)   // downscale + compress
                }
                self.photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCapture { image in
                pendingPhoto = ProgressImage.encode(image)       // downscale + compress
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("Which pose?", isPresented: pendingPoseBinding, titleVisibility: .visible) {
            ForEach([PicPose.front, .side, .back], id: \.rawValue) { pose in
                Button(pose.rawValue.capitalized) { savePendingPhoto(as: pose) }
            }
        }
        .fullScreenCover(item: $picViewer) { context in
            ProgressPicViewer(context: context) { store.vault.readFile(at: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { picsUnlocked = false }   // re-lock when we leave
        }
    }

    // MARK: - photo plumbing

    @State private var photoPickerPresented = false

    private var photoPickerBinding: Binding<Bool> {
        Binding(get: { photoPickerPresented }, set: { photoPickerPresented = $0 })
    }

    private var pendingPoseBinding: Binding<Bool> {
        Binding(get: { pendingPhoto != nil }, set: { if !$0 { pendingPhoto = nil } })
    }

    private func savePendingPhoto(as pose: PicPose) {
        guard let data = pendingPhoto else { return }
        store.addPhoto(data, pose: pose, on: selectedDay)
        pendingPhoto = nil
    }

    /// Open the viewer on `pic`, gating behind Face ID if pics are locked and
    /// we haven't already unlocked this session.
    private func openPics(at pic: ProgressPic) {
        guard let pics = log?.pics, let idx = pics.firstIndex(where: { $0.id == pic.id }) else { return }
        let context = ProgressPicContext(pics: pics, startIndex: idx)
        if lockPhotos && !picsUnlocked {
            Task {
                if await PhotoAuth.authenticate() {
                    picsUnlocked = true
                    picViewer = context
                }
            }
        } else {
            picViewer = context
        }
    }

    // MARK: masthead

    private var masthead: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day())
                .uppercased())
                .font(Typo.eyebrow)
                .tracking(2.2)
                .foregroundStyle(Palette.graphite)
            Spacer()
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.graphite)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    // MARK: weight

    @ViewBuilder
    private var weightBlock: some View {
        // Prefer a weigh-in measured on the selected day; otherwise carry the
        // most recent one forward with an "as of" note (the scale is sparse).
        let measuredToday = log?.metrics
        let carried = measuredToday == nil ? store.recentMetrics(asOf: selectedDay) : nil
        if let metrics = measuredToday ?? carried?.metrics {
            VStack(alignment: .leading, spacing: 2) {
                Text(metrics.weightLbs.formatted(.number.precision(.fractionLength(1))))
                    .font(Typo.numeral)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: metrics.weightLbs))
                HStack(spacing: 10) {
                    Text("lbs")
                        .font(Typo.mono)
                        .foregroundStyle(Palette.graphite)
                    if let delta = store.weeklyDelta(for: selectedDay) {
                        Text("\(delta <= 0 ? "▾" : "▴") \(abs(delta).formatted(.number.precision(.fractionLength(1)))) this week")
                            .font(Typo.mono)
                            .foregroundStyle(Palette.graphite)
                    }
                }
                if let composition = metrics.compositionLine {
                    Text(composition)
                        .font(Typo.monoSmall)
                        .foregroundStyle(Palette.graphite)
                        .padding(.top, 1)
                }
                if targetBodyFatPct > 0, let goal = metrics.fatToLose(targetPct: targetBodyFatPct) {
                    Text("\(goal.fatLbs.formatted(.number.precision(.fractionLength(1)))) lbs of fat to lose · to \(targetBodyFatPct.formatted(.number.precision(.fractionLength(0...1))))%")
                        .font(Typo.monoSmall)
                        .foregroundStyle(Palette.madder)
                        .padding(.top, 1)
                }
                if let carried, let day = carried.day as Date? {
                    Text("as of \(day.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(Typo.monoSmall)
                        .foregroundStyle(Palette.graphite.opacity(0.7))
                }
            }
        } else {
            Text("No weigh-in yet")
                .font(Typo.display)
                .foregroundStyle(Palette.graphite)
        }
    }

    // MARK: workout

    @ViewBuilder
    private var workoutSection: some View {
        let planned = store.stickyWorkout(for: selectedDay)
        let logged = log?.workout?.exercises ?? []
        let suggestions = store.suggestedExercises(for: selectedDay)
        // Explicitly marked rest, or a scheduled rest day left untouched.
        let markedRest = log?.workout?.status == .rest
        let isRest = markedRest || (planned.status == .rest && log?.workout == nil)

        if isRest {
            Menu {
                Button { addingWorkoutExercise = true } label: {
                    Label("Add exercise anyway", systemImage: "plus")
                }
                if markedRest {
                    Button { store.clearWorkout(on: selectedDay) } label: {
                        Label("Not a rest day", systemImage: "arrow.uturn.backward")
                    }
                }
            } label: {
                HStack {
                    Text("Rest day")
                        .font(Typo.display)
                        .foregroundStyle(Palette.graphite)
                    Spacer()
                }
                .cardStock(Palette.chalk)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    sectionHeader("Workout")
                    Spacer()
                    Menu {
                        Button { addingWorkoutExercise = true } label: {
                            Label("Add exercise", systemImage: "plus")
                        }
                        Button {
                            store.saveWorkout(WorkoutEntry(status: .rest), on: selectedDay)
                        } label: {
                            Label("Mark as rest day", systemImage: "moon.zzz")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.madder)
                    }
                    .accessibilityLabel("Add exercise or mark rest")
                }

                // Logged exercises (solid). Any row opens the all-together edit.
                if !logged.isEmpty {
                    ForEach(Array(logged.enumerated()), id: \.offset) { index, exercise in
                        Button {
                            showingWorkoutSheet = true
                        } label: {
                            exerciseRow(exercise, faint: false, divider: index < logged.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                } else if suggestions.isEmpty {
                    emptyLine("No exercises yet.")
                }

                // Suggestions from the scheduled workout (faint): Log all + per-row +.
                if !suggestions.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Suggested · \(planned.title ?? planned.template ?? "plan")")
                            .font(Typo.monoSmall)
                            .foregroundStyle(Palette.graphite)
                        Spacer()
                        Button {
                            store.logAllSuggested(on: selectedDay)
                        } label: {
                            Text("Log all").font(Typo.monoSmall).foregroundStyle(Palette.madder)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 2)
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { _, exercise in
                        Button {
                            store.logExercise(exercise, on: selectedDay)
                        } label: {
                            suggestionRow(exercise)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .cardStock(Palette.chalk)
        }
    }

    /// A logged exercise row — name · notation, with an optional how-to glyph.
    private func exerciseRow(_ exercise: ExerciseEntry, faint: Bool, divider: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(exercise.name)
                .font(Typo.body)
                .foregroundStyle(faint ? Palette.graphite : Palette.ink)
            if let link = firstLink(for: exercise) { linkGlyph(link) }
            Spacer(minLength: 12)
            Text(exercise.notation)
                .font(Typo.mono)
                .foregroundStyle(Palette.graphite)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if divider { Rectangle().fill(Palette.hairline).frame(height: 0.5) }
        }
    }

    /// A suggested (not-yet-logged) exercise — faint, with a leading + to log it.
    private func suggestionRow(_ exercise: ExerciseEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.system(size: 13))
                .foregroundStyle(Palette.madder)
            Text(exercise.name)
                .font(Typo.body)
                .foregroundStyle(Palette.graphite)
            if let link = firstLink(for: exercise) { linkGlyph(link) }
            Spacer(minLength: 12)
            Text(exercise.notation)
                .font(Typo.mono)
                .foregroundStyle(Palette.graphite)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    /// Tap-to-open how-to link glyph.
    @ViewBuilder
    private func linkGlyph(_ link: ExerciseLink) -> some View {
        Button {
            if let url = URL(string: link.url) { openURL(url) }
        } label: {
            Image(systemName: "play.circle")
                .font(.footnote)
                .foregroundStyle(Palette.madder)
        }
        .buttonStyle(.plain)
    }

    /// The first how-to link for a workout exercise, resolved from the library.
    private func firstLink(for exercise: ExerciseEntry) -> ExerciseLink? {
        store.exercise(exercise.exerciseId)?.links.first
    }

    /// Build a loggable entry for a library exercise picked from the header +.
    private func loggableEntry(for exercise: Exercise) -> ExerciseEntry {
        guard exercise.muscle != "cardio" else {
            return ExerciseEntry(name: exercise.name, exerciseId: exercise.key, durationMin: 20)
        }
        let set = SetEntry(reps: exercise.defaultReps, weightLbs: exercise.defaultWeight(for: Sex.current))
        return ExerciseEntry(name: exercise.name, exerciseId: exercise.key,
                             sets: Array(repeating: set, count: 3))
    }

    // MARK: food

    private var foodSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeader("Food")
                Spacer()
                Button {
                    showingFoodSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.madder)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add food")
            }
            if let food = log?.food, !food.isEmpty {
                ForEach(Array(food.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        // Only DB foods have servings to scale; free text/photos don't.
                        if entry.foodId != nil { editingFood = entry }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(entry.at)
                                .font(Typo.mono)
                                .foregroundStyle(Palette.graphite)
                            Text(foodLabel(entry))
                                .font(Typo.body)
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                            if let m = store.macros(for: entry) {
                                Text("\(Int(m.calories.rounded()))")
                                    .font(Typo.mono)
                                    .foregroundStyle(Palette.graphite)
                            }
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        if index < food.count - 1 {
                            Rectangle().fill(Palette.hairline).frame(height: 0.5)
                        }
                    }
                    .contextMenu {
                        if entry.foodId != nil {
                            Button {
                                editingFood = entry
                            } label: {
                                Label("Edit servings", systemImage: "slider.horizontal.3")
                            }
                        }
                        Button(role: .destructive) {
                            store.removeFood(entry, on: selectedDay)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } else if store.plannedStaples(for: selectedDay).isEmpty {
                emptyLine("Nothing logged yet.")
            }
            plannedStaples
            macroTotals
        }
    }

    /// The active meal plan's not-yet-logged staples, shown faint with a tap to
    /// log — one at a time, or all at once. They drop off as you add them.
    @ViewBuilder
    private var plannedStaples: some View {
        let planned = store.plannedStaples(for: selectedDay)
        if !planned.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text("From your plan").font(Typo.monoSmall).foregroundStyle(Palette.graphite)
                Spacer()
                Button {
                    store.logStaples(on: selectedDay)
                } label: {
                    Text("Add all").font(Typo.monoSmall).foregroundStyle(Palette.madder)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
            .padding(.bottom, 2)
            ForEach(planned) { staple in
                Button {
                    store.addFood(staple, on: selectedDay)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.madder)
                        Text(foodLabel(staple))
                            .font(Typo.body)
                            .foregroundStyle(Palette.graphite)
                        Spacer(minLength: 0)
                        if let m = store.macros(for: staple) {
                            Text("\(Int(m.calories.rounded()))")
                                .font(Typo.mono)
                                .foregroundStyle(Palette.graphite)
                        }
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "Kimchi Rice ×2" for DB foods, else the free text.
    private func foodLabel(_ entry: FoodEntry) -> String {
        if entry.foodId != nil {
            let servings = entry.servings ?? 1
            let suffix = servings == 1 ? "" : " ×\(servings.formatted(.number.precision(.fractionLength(0...2))))"
            return (entry.text ?? "food") + suffix
        }
        return entry.text ?? entry.recipe ?? "photo"
    }

    @ViewBuilder
    private var macroTotals: some View {
        let total = store.macros(for: selectedDay)
        if !total.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(Int(total.calories.rounded())) kcal")
                        .foregroundStyle(Palette.ink)
                    Text("· \(Int(total.proteinG.rounded()))P · \(Int(total.carbsG.rounded()))C · \(Int(total.fatG.rounded()))F")
                        .foregroundStyle(Palette.graphite)
                }
                // Second line: the extras worth watching on a cut, when present.
                if total.fiberG > 0 || total.totalSugarsG > 0 || total.sodiumMg > 0 || total.satFatG > 0 {
                    Text("\(Int(total.fiberG.rounded()))g fiber · \(Int(total.totalSugarsG.rounded()))g sugar · \(Int(total.satFatG.rounded()))g sat · \(Int(total.sodiumMg.rounded()))mg Na")
                        .foregroundStyle(Palette.graphite)
                }
            }
            .font(Typo.mono)
            .padding(.top, 10)
        }
    }

    /// Calories out (resting + activity) vs in, with macro targets — its own card.
    /// Shown as soon as there's a resting burn to compute, even before logging.
    @ViewBuilder
    private var energySection: some View {
        let b = budget
        if let out = b.caloriesOut, let rest = b.baselineBurn {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Energy")
                VStack(alignment: .leading, spacing: 4) {
                    if let bal = b.balance {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(Int(abs(bal).rounded()))")
                                .font(Typo.display)
                                .foregroundStyle(bal >= 0 ? Palette.ink : Palette.madder)
                            Text(bal >= 0 ? "kcal deficit" : "kcal surplus")
                                .font(Typo.mono)
                                .foregroundStyle(Palette.graphite)
                        }
                    }
                    Text("\(Int(out.rounded())) out · \(Int(b.intake.calories.rounded())) in")
                        .font(Typo.mono)
                        .foregroundStyle(Palette.ink)
                    Text("resting \(Int(rest.rounded())) + active \(Int(b.activeKcal.rounded()))")
                        .font(Typo.monoSmall)
                        .foregroundStyle(Palette.graphite)
                    if let target = b.targetCalories {
                        Text("target \(Int(target.rounded())) kcal in")
                            .font(Typo.mono)
                            .foregroundStyle(Palette.graphite)
                            .padding(.top, 2)
                    }
                    if let p = b.proteinTarget, let c = b.carbTarget, let f = b.fatTarget {
                        Text("P \(Int(b.intake.proteinG.rounded()))/\(Int(p.rounded())) · C \(Int(b.intake.carbsG.rounded()))/\(Int(c.rounded())) · F \(Int(b.intake.fatG.rounded()))/\(Int(f.rounded())) g")
                            .font(Typo.mono)
                            .foregroundStyle(Palette.graphite)
                    }
                }
            }
            .cardStock(Palette.mist)
        }
    }

    // MARK: pics

    private var picsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Pics")
            HStack(spacing: 12) {
                if let pics = log?.pics, !pics.isEmpty {
                    ForEach(pics) { pic in
                        picThumb(pic)
                    }
                }
                Menu {
                    if CameraCapture.isAvailable {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take photo", systemImage: "camera")
                        }
                    }
                    Button {
                        photoPickerPresented = true
                    } label: {
                        Label("Choose from library", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: 64, height: 84)
                        .overlay {
                            Image(systemName: "camera")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Palette.madder)
                        }
                }
                .accessibilityLabel("Add progress photo")
            }
        }
    }

    private func picThumb(_ pic: ProgressPic) -> some View {
        PicThumb(
            pic: pic,
            data: store.vault.readFile(at: pic.path),
            locked: lockPhotos && !picsUnlocked
        ) { openPics(at: pic) }
    }

    // MARK: sleep (nightly stages from sleep.csv)

    @ViewBuilder
    private var sleepSection: some View {
        if let sleep = store.sleep(on: selectedDay), let asleep = sleep["asleep_min"], asleep > 0 {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    sectionHeader("Sleep")
                    Spacer()
                    Text("\(hoursMinutes(asleep)) asleep")
                        .font(Typo.mono)
                        .foregroundStyle(Palette.ink)
                }
                // Stage breakdown, in the order the night is usually read.
                let stages: [(String, String)] = [
                    ("deep_min", "Deep"), ("core_min", "Core"),
                    ("rem_min", "REM"), ("awake_min", "Awake"),
                ]
                let present = stages.compactMap { key, label -> (String, Double)? in
                    guard let m = sleep[key], m > 0 else { return nil }
                    return (label, m)
                }
                if !present.isEmpty {
                    HStack(spacing: 16) {
                        ForEach(present, id: \.0) { label, minutes in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(hoursMinutes(minutes)).font(Typo.mono).foregroundStyle(Palette.ink)
                                Text(label).font(Typo.monoSmall).foregroundStyle(Palette.graphite)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                if let inBed = sleep["in_bed_min"], inBed > 0 {
                    Text("\(hoursMinutes(inBed)) in bed")
                        .font(Typo.monoSmall)
                        .foregroundStyle(Palette.graphite)
                }
            }
            .cardStock(Palette.sage)
        }
    }

    /// Minutes → "6h 58m" / "42m".
    private func hoursMinutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60
        let m = total % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    // MARK: Apple Watch sessions (recorded workouts.csv for the day)

    @ViewBuilder
    private var sessionsSection: some View {
        let sessions = store.workoutSessions(on: selectedDay)
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Sessions")
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(session.start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                            .font(Typo.mono)
                            .foregroundStyle(Palette.graphite)
                        Text(session.type)
                            .font(Typo.body)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                        Text(sessionDetail(session))
                            .font(Typo.mono)
                            .foregroundStyle(Palette.graphite)
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) {
                        if index < sessions.count - 1 {
                            Rectangle().fill(Palette.hairline).frame(height: 0.5)
                        }
                    }
                }
            }
            .cardStock(Palette.sage)
        }
    }

    /// "45m · 320 kcal · 128 bpm" — whatever the watch recorded.
    private func sessionDetail(_ session: WorkoutRecord) -> String {
        var parts = ["\(Int(session.durationMin.rounded()))m"]
        if let kcal = session.energyKcal { parts.append("\(Int(kcal.rounded())) kcal") }
        if let hr = session.avgHR { parts.append("\(Int(hr.rounded())) bpm") }
        return parts.joined(separator: " · ")
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

/// The day's journal note, isolated in its own view with local draft state.
/// Keeping the text field out of `TodayView` means each keystroke re-renders
/// only this small view — not the 120-day spine, food math, and charts — which
/// is what kept the keyboard sluggish/unresponsive on the first tap. Commits on
/// blur and on teardown (the parent gives it `.id(day)`, so switching days
/// rebuilds it and flushes the day we left).
private struct DayNotesEditor: View {
    let day: Date
    let initialText: String
    let onCommit: (String?) -> Void

    @State private var draft: String
    @FocusState private var focused: Bool

    init(day: Date, initialText: String, onCommit: @escaping (String?) -> Void) {
        self.day = day
        self.initialText = initialText
        self.onCommit = onCommit
        _draft = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(Typo.display)
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 6)
            TextField("How did today feel?", text: $draft, axis: .vertical)
                .font(Typo.body)
                .foregroundStyle(Palette.ink)
                .tint(Palette.madder)
                .lineLimit(4...10)
                .focused($focused)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .background(Palette.chalk.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
        }
        .onDisappear { commit() }
        .toolbar {
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                        .foregroundStyle(Palette.madder)
                }
            }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != initialText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        onCommit(trimmed.isEmpty ? nil : trimmed)
    }
}

#Preview {
    TodayView()
        .environment(LogStore())
}

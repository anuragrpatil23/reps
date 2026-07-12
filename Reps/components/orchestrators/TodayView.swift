import SwiftUI
import PhotosUI

/// The day page — the whole app in one calm ledger sheet.
struct TodayView: View {
    @Environment(LogStore.self) private var store
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var showingWorkoutSheet = false
    @State private var showingFoodSheet = false
    @State private var showingSettings = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingPhoto: Data?
    @State private var showingCamera = false
    @State private var noteDraft = ""
    @State private var noteDay: Date?
    @FocusState private var noteFocused: Bool

    private var log: DailyLog? { store.log(for: selectedDay) }

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
                        ActivityLineView(activity: activity)
                            .cardStock(Palette.sage)
                    }
                    workoutSection
                    foodSection
                        .cardStock(Palette.butter)
                    picsSection
                    notesSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable { await store.syncHealth(around: selectedDay) }
            SpineView(
                days: spineDays,
                marks: spineDays.map { DayMark(log: store.log(for: $0)) },
                selected: $selectedDay
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .background(Palette.paper.ignoresSafeArea())
        .animation(.easeOut(duration: 0.18), value: selectedDay)
        .task {
            if !store.loaded { store.load() }
            syncNote()
            await store.syncHealth(around: selectedDay)
        }
        .onChange(of: selectedDay) {
            commitNote()   // save the day we're leaving
            syncNote()     // load the day we're entering
        }
        .toolbar {
            if noteFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { noteFocused = false }
                        .foregroundStyle(Palette.madder)
                }
            }
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
        let workout = log?.workout ?? store.stickyWorkout(for: selectedDay)
        if workout.status == .rest {
            HStack {
                Text("Rest day")
                    .font(Typo.display)
                    .foregroundStyle(Palette.graphite)
                Spacer()
            }
            .cardStock(Palette.chalk)
        } else {
            Button {
                showingWorkoutSheet = true
            } label: {
                WorkoutCardView(workout: workout)
            }
            .buttonStyle(.plain)
        }
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
                    .overlay(alignment: .bottom) {
                        if index < food.count - 1 {
                            Rectangle().fill(Palette.hairline).frame(height: 0.5)
                        }
                    }
                }
                macroTotals
            } else {
                emptyLine("Nothing logged yet.")
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
            HStack(spacing: 6) {
                Text("\(Int(total.calories.rounded())) kcal")
                    .foregroundStyle(Palette.ink)
                Text("· \(Int(total.proteinG.rounded()))P · \(Int(total.carbsG.rounded()))C · \(Int(total.fatG.rounded()))F")
                    .foregroundStyle(Palette.graphite)
            }
            .font(Typo.mono)
            .padding(.top, 10)
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

    @ViewBuilder
    private func picThumb(_ pic: ProgressPic) -> some View {
        ZStack {
            if let data = store.vault.readFile(at: pic.path), let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Palette.chalk
            }
        }
        .frame(width: 64, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .bottom) {
            Text(pic.pose.rawValue)
                .font(Typo.monoSmall)
                .foregroundStyle(Palette.paper)
                .shadow(color: Palette.ink.opacity(0.6), radius: 2)
                .padding(.bottom, 6)
        }
    }

    // MARK: notes (the markdown body — the day's journal)

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Notes")
            TextField("How did today feel?", text: $noteDraft, axis: .vertical)
                .font(Typo.body)
                .foregroundStyle(Palette.ink)
                .tint(Palette.madder)
                .lineLimit(1...10)
                .focused($noteFocused)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.chalk.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: noteFocused) { _, focused in
                    if !focused { commitNote() }
                }
        }
    }

    /// Load the selected day's note into the editable draft.
    private func syncNote() {
        noteDraft = store.log(for: selectedDay)?.note ?? ""
        noteDay = selectedDay
    }

    /// Persist the draft to the day it belongs to, if it changed.
    private func commitNote() {
        guard let day = noteDay else { return }
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = store.log(for: day)?.note ?? ""
        if trimmed != existing {
            store.saveNote(trimmed.isEmpty ? nil : trimmed, on: day)
        }
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
        .environment(LogStore())
}

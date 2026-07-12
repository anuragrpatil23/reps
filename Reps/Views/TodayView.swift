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
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable { await store.refreshHealth(for: selectedDay) }
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
            await store.refreshHealth(for: selectedDay)
        }
        .onChange(of: selectedDay) {
            Task { await store.refreshHealth(for: selectedDay) }
        }
        .sheet(isPresented: $showingWorkoutSheet) {
            WorkoutEditSheet(draft: log?.workout ?? store.stickyWorkout(for: selectedDay)) { final in
                store.saveWorkout(final, on: selectedDay)
            }
        }
        .sheet(isPresented: $showingFoodSheet) {
            FoodEntrySheet { entry in
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
                if let data = try? await photoItem.loadTransferable(type: Data.self) {
                    pendingPhoto = data
                }
                self.photoItem = nil
            }
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
        if let weight = log?.metrics?.weightLbs {
            VStack(alignment: .leading, spacing: 2) {
                Text(weight.formatted(.number.precision(.fractionLength(1))))
                    .font(Typo.numeral)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: weight))
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
            }
        } else {
            Text("No weigh-in")
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
                        Text(entry.text ?? entry.recipe ?? "photo")
                            .font(Typo.body)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) {
                        if index < food.count - 1 {
                            Rectangle().fill(Palette.hairline).frame(height: 0.5)
                        }
                    }
                }
            } else {
                emptyLine("Nothing logged yet.")
            }
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
                Button {
                    photoPickerPresented = true
                } label: {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: 64, height: 84)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Palette.madder)
                        }
                }
                .buttonStyle(.plain)
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

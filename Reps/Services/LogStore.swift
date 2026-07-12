import Foundation
import SwiftUI

/// The app's single observable store. In-memory cache over the vault files —
/// rebuildable from a folder rescan at any time (contract §6), so losing it
/// costs nothing. All writes go file-first through VaultStore.
@MainActor
@Observable
final class LogStore {
    let vault = VaultStore()

    private(set) var logsByDay: [Date: DailyLog] = [:]
    private(set) var templates: [WorkoutTemplate] = []
    private(set) var loaded = false
    var lastError: String?

    var vaultConfigured: Bool { vault.isConfigured }

    // MARK: - Load / rebuild

    func load() {
        logsByDay = [:]
        for date in vault.listLogDates() {
            if let log = vault.readDailyLog(for: date) {
                logsByDay[Calendar.current.startOfDay(for: date)] = log
            }
        }
        let fromVault = vault.readTemplates()
        templates = fromVault.isEmpty ? [.builtinPushA] : fromVault
        loaded = true
    }

    func connectVault(to url: URL) {
        do {
            try vault.setRoot(url)
            load()
        } catch {
            lastError = "Couldn't save vault folder access: \(error.localizedDescription)"
        }
    }

    // MARK: - Reads

    func log(for date: Date) -> DailyLog? {
        logsByDay[Calendar.current.startOfDay(for: date)]
    }

    func weeklyDelta(for date: Date) -> Double? {
        guard let current = log(for: date)?.metrics?.weightLbs else { return nil }
        for daysBack in 6...8 {
            guard let prior = Calendar.current.date(byAdding: .day, value: -daysBack, to: date),
                  let weight = log(for: prior)?.metrics?.weightLbs else { continue }
            return current - weight
        }
        return nil
    }

    /// Sticky defaults: last completed workout → template baseline.
    func stickyWorkout(for date: Date) -> WorkoutEntry {
        let day = Calendar.current.startOfDay(for: date)
        let last = logsByDay.values
            .filter { $0.date < day }
            .sorted { $0.date > $1.date }
            .compactMap(\.workout)
            .first { $0.status == .done || $0.status == .partial }
        if let last {
            var draft = last
            draft.status = .skipped   // not logged yet today
            draft.startedAt = nil
            return draft
        }
        let template = templates.first ?? .builtinPushA
        return WorkoutEntry(
            status: .skipped, template: template.key, title: template.title,
            exercises: template.exercises
        )
    }

    // MARK: - Writes (file-first, then cache)

    func upsert(_ log: DailyLog) {
        var toSave = log
        if toSave.createdAt == nil { toSave.createdAt = Date() }
        do {
            try vault.writeDailyLog(toSave)
            logsByDay[Calendar.current.startOfDay(for: toSave.date)] = toSave
            lastError = nil
        } catch {
            lastError = "Couldn't save to vault: \(error.localizedDescription)"
        }
    }

    private func editableLog(for date: Date) -> DailyLog {
        log(for: date) ?? DailyLog(date: Calendar.current.startOfDay(for: date))
    }

    func saveWorkout(_ workout: WorkoutEntry, on date: Date) {
        var log = editableLog(for: date)
        log.workout = workout
        upsert(log)
    }

    func addFood(_ entry: FoodEntry, on date: Date) {
        var log = editableLog(for: date)
        log.food.append(entry)
        log.food.sort { $0.at < $1.at }
        upsert(log)
    }

    func addPhoto(_ jpeg: Data, pose: PicPose, on date: Date) {
        do {
            let path = try vault.savePhoto(jpeg, date: date, pose: pose)
            var log = editableLog(for: date)
            log.pics.append(ProgressPic(path: path, pose: pose))
            upsert(log)
        } catch {
            lastError = "Couldn't save photo: \(error.localizedDescription)"
        }
    }

    /// Pulls HealthKit data for the day and stamps it into the log.
    /// Only writes when something actually changed.
    func refreshHealth(for date: Date) async {
        guard vaultConfigured, HealthKitService.isAvailable else { return }
        let metrics = await HealthKitService.metrics(for: date)
        let activity = await HealthKitService.activity(for: date)
        guard metrics != nil || activity != nil else { return }
        var log = editableLog(for: date)
        var changed = false
        if let metrics, log.metrics?.weightLbs != metrics.weightLbs
            || log.metrics?.bodyFatPct != metrics.bodyFatPct {
            log.metrics = metrics
            changed = true
        }
        if let activity, log.activity?.moveKcal != activity.moveKcal
            || log.activity?.exerciseMin != activity.exerciseMin
            || log.activity?.standHours != activity.standHours
            || log.activity?.steps != activity.steps {
            log.activity = activity
            changed = true
        }
        if changed { upsert(log) }
    }
}

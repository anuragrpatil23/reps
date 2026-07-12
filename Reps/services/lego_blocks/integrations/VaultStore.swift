import Foundation

/// File access to the vault's `Body/` folder — the source of truth.
/// The app owns (sole writer) `sffit/log/`, `sffit/templates/`, and
/// `sffit/progress-pics/`; everything else is read-only per the contract.
/// Folder access persists via a security-scoped bookmark; on the simulator
/// it falls back to the real iCloud path for development.
@MainActor
final class VaultStore {
    private static let bookmarkKey = "vault.body.bookmark"

    private(set) var rootURL: URL?
    private var isSecurityScoped = false

    init() {
        restore()
    }

    var isConfigured: Bool { rootURL != nil }

    // MARK: - Configuration

    private func restore() {
        if let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                bookmarkDataIsStale: &stale
            ) {
                rootURL = url
                isSecurityScoped = true
                if stale { try? persistBookmark(for: url) }
                return
            }
        }
        #if targetEnvironment(simulator)
        // Simulator shares the host filesystem — use a dev vault directly.
        // REPS_VAULT_PATH overrides (for testing against a scratch folder);
        // otherwise fall back to the real iCloud vault.
        let devPath = ProcessInfo.processInfo.environment["REPS_VAULT_PATH"]
            ?? "/Users/patila06/Library/Mobile Documents/iCloud~md~obsidian/Documents/Long-Term-Memory-iCloud/lifeblood_systems/Understanding Myself/Body"
        if FileManager.default.fileExists(atPath: devPath) {
            rootURL = URL(fileURLWithPath: devPath)
            isSecurityScoped = false
        }
        #endif
    }

    /// Called with the URL from the folder picker (`Body/`).
    func setRoot(_ url: URL) throws {
        try persistBookmark(for: url)
        rootURL = url
        isSecurityScoped = true
    }

    private func persistBookmark(for url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData()
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
    }

    private func withAccess<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard let root = rootURL else { return nil }
        let accessing = isSecurityScoped && root.startAccessingSecurityScopedResource()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }
        return try body(root)
    }

    // MARK: - Paths

    private func logURL(for date: Date, root: URL) -> URL {
        let day = DailyLogCodec.dayString(date)
        let year = String(day.prefix(4))
        return root.appending(path: "sffit/log/\(year)/\(day).md")
    }

    // MARK: - Daily logs

    func readDailyLog(for date: Date) -> DailyLog? {
        withAccess { root in
            let url = logURL(for: date, root: root)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return DailyLogCodec.parseDailyLog(text, date: date)
        } ?? nil
    }

    /// Atomic write (temp + rename via .atomic) — never a partial file.
    func writeDailyLog(_ log: DailyLog) throws {
        _ = try withAccess { root in
            let url = logURL(for: log.date, root: root)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let text = try DailyLogCodec.markdown(for: log)
            try Data(text.utf8).write(to: url, options: .atomic)
        }
    }

    /// Remove a day's markdown file (used by cleanup once its telemetry is
    /// safely in the CSVs). No-op if the file isn't there.
    func deleteLog(for date: Date) throws {
        _ = try withAccess { root in
            let url = logURL(for: date, root: root)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    /// All day-dates that have a log file on disk.
    func listLogDates() -> [Date] {
        withAccess { root in
            let logRoot = root.appending(path: "sffit/log")
            guard let files = FileManager.default.enumerator(
                at: logRoot, includingPropertiesForKeys: nil) else { return [] }
            return files.compactMap { item -> Date? in
                guard let url = item as? URL, url.pathExtension == "md" else { return nil }
                return DailyLogCodec.day(from: url.deletingPathExtension().lastPathComponent)
            }
        } ?? []
    }

    // MARK: - Templates

    func readTemplates() -> [WorkoutTemplate] {
        withAccess { root in
            let dir = root.appending(path: "sffit/templates")
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { return [] }
            return files
                .filter { $0.pathExtension == "md" }
                .compactMap { url in
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                    return DailyLogCodec.parseTemplate(text)
                }
        } ?? []
    }

    // MARK: - Progress pics

    /// Saves JPEG data and returns the vault-relative path for the log entry.
    func savePhoto(_ data: Data, date: Date, pose: PicPose) throws -> String {
        try withAccess { root -> String in
            let day = DailyLogCodec.dayString(date)
            let month = String(day.prefix(7))
            let dir = root.appending(path: "sffit/progress-pics/\(month)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var name = "\(day)_\(pose.rawValue).jpg"
            var counter = 2
            while FileManager.default.fileExists(atPath: dir.appending(path: name).path) {
                name = "\(day)_\(pose.rawValue)_\(counter).jpg"
                counter += 1
            }
            try data.write(to: dir.appending(path: name), options: .atomic)
            return "sffit/progress-pics/\(month)/\(name)"
        } ?? { throw CocoaError(.fileNoSuchFile) }()
    }

    /// Loads image data for a vault-relative path (for thumbnails).
    func readFile(at relativePath: String) -> Data? {
        withAccess { root in
            try? Data(contentsOf: root.appending(path: relativePath))
        } ?? nil
    }

    // MARK: - Telemetry CSVs

    private func readText(_ relativePath: String) -> String? {
        withAccess { root in
            try? String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
        } ?? nil
    }

    private func writeText(_ text: String, to relativePath: String) throws {
        _ = try withAccess { root in
            let url = root.appending(path: relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        }
    }

    func readBodyComposition() -> [Date: BodyMetrics] {
        guard let text = readText(TelemetryCsv.bodyCompositionPath) else { return [:] }
        return TelemetryCsv.parseBodyComposition(text)
    }

    func writeBodyComposition(_ metrics: [Date: BodyMetrics]) throws {
        try writeText(TelemetryCsv.formatBodyComposition(metrics), to: TelemetryCsv.bodyCompositionPath)
    }

    func readActivity() -> [Date: ActivitySummary] {
        guard let text = readText(TelemetryCsv.activityPath) else { return [:] }
        return TelemetryCsv.parseActivity(text)
    }

    func writeActivity(_ activity: [Date: ActivitySummary]) throws {
        try writeText(TelemetryCsv.formatActivity(activity), to: TelemetryCsv.activityPath)
    }

    // MARK: - Curated Apple Health CSVs

    func readHealth(_ path: String, columns: [String]) -> [Date: [String: Double]] {
        guard let text = readText(path) else { return [:] }
        return HealthCsv.parse(text, columns: columns)
    }

    func writeHealth(_ rows: [Date: [String: Double]], columns: [String], to path: String) throws {
        try writeText(HealthCsv.format(rows, columns: columns), to: path)
    }

    func readWorkouts() -> [WorkoutRecord] {
        guard let text = readText(HealthCsv.workoutsPath) else { return [] }
        return HealthCsv.parseWorkouts(text)
    }

    func writeWorkouts(_ workouts: [WorkoutRecord]) throws {
        try writeText(HealthCsv.formatWorkouts(workouts), to: HealthCsv.workoutsPath)
    }

    // MARK: - Food database

    func readFoods() -> [Food] {
        guard let text = readText(FoodsCsv.path) else { return [] }
        return FoodsCsv.parse(text)
    }

    func writeFoods(_ foods: [Food]) throws {
        try writeText(FoodsCsv.format(foods), to: FoodsCsv.path)
    }
}

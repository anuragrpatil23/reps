import Foundation

/// A training block: an ordered rotation of workout templates, the weekdays that
/// are always rest, and an anchor date the rotation counts from. The rotation is
/// *continuous* — it walks across training days (skipping rest days) week after
/// week, so when the rotation length doesn't divide the training-days-per-week
/// the same weekday drifts to a new workout each week. Grouped by phase so a cut
/// block and a bulk block are separate programs you switch between.
///
/// Stored one-per-file at `sffit/programs/<key>.md` (see docs/DATA-CONTRACT.md).
struct Program: Identifiable, Sendable, Equatable {
    var key: String
    var title: String
    var phase: TrainingPhase
    var rotation: [String]          // template keys, in cycle order
    var restDays: Set<Weekday>      // weekdays that are always rest
    var anchor: Date                // the day rotation[0] is performed

    var id: String { key }

    var trainingDaysPerWeek: Int { max(0, 7 - restDays.count) }

    func isRestDay(_ date: Date) -> Bool {
        restDays.contains(Weekday(date))
    }

    /// Which rotation slot lands on `date`, or nil if it's a rest day, the
    /// rotation is empty, or `date` is before the anchor.
    func rotationIndex(on date: Date) -> Int? {
        guard !rotation.isEmpty, trainingDaysPerWeek > 0, !isRestDay(date) else { return nil }
        let cal = Calendar.current
        let anchorDay = cal.startOfDay(for: anchor)
        let target = cal.startOfDay(for: date)
        guard let dayDelta = cal.dateComponents([.day], from: anchorDay, to: target).day,
              dayDelta >= 0 else { return nil }

        // Training days in [anchor, target): whole weeks contribute a fixed count
        // (rest days are weekday-based), the remainder is counted directly.
        let fullWeeks = dayDelta / 7
        let remainder = dayDelta % 7
        var partial = 0
        for offset in 0..<remainder {
            if let day = cal.date(byAdding: .day, value: offset, to: anchorDay), !isRestDay(day) {
                partial += 1
            }
        }
        let ordinal = fullWeeks * trainingDaysPerWeek + partial
        return ordinal % rotation.count
    }

    /// The template key scheduled on `date` (nil on rest / pre-anchor days).
    func scheduledTemplateKey(on date: Date) -> String? {
        rotationIndex(on: date).map { rotation[$0] }
    }
}

/// The training phase a program belongs to — the grouping axis.
enum TrainingPhase: String, CaseIterable, Sendable, Identifiable {
    case cut, bulk, maintenance, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cut: "Cut"
        case .bulk: "Bulk"
        case .maintenance: "Maintenance"
        case .other: "Other"
        }
    }
}

/// A day of the week, numbered to match `Calendar.component(.weekday, …)`
/// (Sunday = 1 … Saturday = 7) so conversion is a straight init.
enum Weekday: Int, CaseIterable, Sendable, Identifiable, Comparable {
    case sun = 1, mon, tue, wed, thu, fri, sat

    var id: Int { rawValue }

    init(_ date: Date) {
        self = Weekday(rawValue: Calendar.current.component(.weekday, from: date)) ?? .sun
    }

    /// Lowercase three-letter code used in the data contract (mon, tue, …).
    var code: String {
        switch self {
        case .sun: "sun"; case .mon: "mon"; case .tue: "tue"; case .wed: "wed"
        case .thu: "thu"; case .fri: "fri"; case .sat: "sat"
        }
    }

    var short: String { code.capitalized }

    static func from(code: String) -> Weekday? {
        allCases.first { $0.code == code.lowercased() }
    }

    /// Monday-first ordering for UI (the training week starts Monday here).
    private var mondayFirstRank: Int { self == .sun ? 7 : rawValue - 1 }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.mondayFirstRank < rhs.mondayFirstRank
    }
}

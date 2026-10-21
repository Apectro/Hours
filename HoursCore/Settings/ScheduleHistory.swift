import Foundation

/// One contracted week, and the day it took effect.
struct ScheduleVersion: Hashable, Codable, Sendable {
    /// The first day this week applies to. Nil is "since always": the version
    /// every history starts with.
    var from: CalendarDate?
    var schedule: WorkSchedule

    init(from: CalendarDate?, schedule: WorkSchedule) {
        self.from = from
        self.schedule = schedule
    }

    private enum CodingKeys: String, CodingKey {
        case from, schedule
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            from: container.lenientOptional(.from, CalendarDate.self),
            schedule: container.lenient(.schedule, WorkSchedule())
        )
    }
}

/// A job's contracted week over time.
///
/// Contracts change — a four-day week from November, fewer hours after a
/// child is born — and the months before the change were worked, and possibly
/// handed in, under the old one. With a single schedule, saving the new week
/// rewrote every month since the app was installed, closed ones and the
/// running balance included. So a week is kept with the day it started, and
/// everything that reads a schedule for a date reads the version in force on
/// that date: the latest one that had started by then.
///
/// Never empty, sorted by start, and the first version is always "since
/// always", so every date has exactly one answer.
struct ScheduleHistory: Hashable, Sendable {
    private(set) var versions: [ScheduleVersion]

    init(_ schedule: WorkSchedule = WorkSchedule()) {
        self.versions = [ScheduleVersion(from: nil, schedule: schedule)]
    }

    /// Accepts whatever a stored list holds and makes it a history: sorted,
    /// one version per start day (the last one listed wins), and starting
    /// "since always" — a first version with a date would leave the days
    /// before it with no schedule at all, so it is read as the beginning.
    init(versions: [ScheduleVersion]) {
        var byStart: [Int: ScheduleVersion] = [:]
        var order: [Int] = []
        for version in versions {
            let key = version.from?.key ?? 0
            if byStart[key] == nil { order.append(key) }
            byStart[key] = version
        }
        var sorted = order.sorted().compactMap { byStart[$0] }
        if sorted.isEmpty { sorted = [ScheduleVersion(from: nil, schedule: WorkSchedule())] }
        sorted[0].from = nil
        self.versions = sorted
    }

    /// The week in force on `date`.
    func schedule(on date: CalendarDate) -> WorkSchedule {
        versions.last { version in version.from.map { $0 <= date } ?? true }?.schedule
            ?? versions[0].schedule
    }

    /// The newest version, which may not have started yet. While there is
    /// one version, it is the schedule, full stop.
    ///
    /// Setting it edits that version in place without making a new one. That
    /// is what an older version of the app does when it writes `schedule`,
    /// and what someone means when they correct a version rather than change
    /// their contract.
    var latest: WorkSchedule {
        get { versions[versions.count - 1].schedule }
        set { versions[versions.count - 1].schedule = newValue }
    }

    var hasChanges: Bool { versions.count > 1 }

    /// The week is `schedule` from `date` onward.
    ///
    /// Versions starting on or after `date` are replaced: saving a week from
    /// 16 November says what the week is from then on, and a change planned
    /// for December was a change to the week being replaced. A nil `date` is
    /// "it was always like this", and leaves a single version.
    mutating func change(to schedule: WorkSchedule, from date: CalendarDate?) {
        guard let date else {
            versions = [ScheduleVersion(from: nil, schedule: schedule)]
            return
        }
        versions.removeAll { version in version.from.map { $0 >= date } ?? false }
        versions.append(ScheduleVersion(from: date, schedule: schedule))
    }

    /// Takes back the change that started on `date`, so the version before it
    /// runs on in its place. The version since always cannot be removed;
    /// there would be nothing left for the earliest days.
    mutating func removeChange(from date: CalendarDate) {
        versions.removeAll { $0.from == date }
    }

    /// The closed months a change from `date` would rewrite, in order — every
    /// one from the month `date` falls in, or every one at all for "it was
    /// always like this". Said before saving, so a timesheet that has been
    /// handed in does not change behind the person's back.
    func closedMonths(affectedByChangeFrom date: CalendarDate?, lock: MonthLock) -> [YearMonth] {
        lock.months
            .filter { month in date.map { month >= $0.yearMonth } ?? true }
            .sorted()
    }
}

extension ScheduleHistory: Codable {
    /// Stored as the list of versions alone.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(versions: try container.decode([ScheduleVersion].self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(versions)
    }
}

extension KeyedDecodingContainer {
    /// A schedule history stored the way `Job` and `AppSettings` store theirs:
    /// the list under `versionsKey` and, for the versions of the app that only
    /// know one week, the newest week under `scheduleKey`.
    ///
    /// Settings written before versions existed have only the week, and read
    /// as one version since always. When both are present and disagree, an
    /// older app edited the week after a newer one wrote the list, and that
    /// edit is the most recent thing anybody did: it lands on the newest
    /// version and the earlier ones are kept.
    func scheduleHistory(versionsKey: Key, scheduleKey: Key) -> ScheduleHistory {
        let week = lenientOptional(scheduleKey, WorkSchedule.self)
        guard var history = lenientOptional(versionsKey, ScheduleHistory.self) else {
            return ScheduleHistory(week ?? WorkSchedule())
        }
        if let week, week != history.latest { history.latest = week }
        return history
    }
}

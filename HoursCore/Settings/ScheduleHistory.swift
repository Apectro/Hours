import Foundation

/// A job's contracted week over time; see `DatedHistory`.
typealias ScheduleHistory = DatedHistory<WorkSchedule>

/// One contracted week, and the day it took effect.
typealias ScheduleVersion = DatedVersion<WorkSchedule>

extension WorkSchedule: DatedValue {
    /// What versions were stored under before anything else was dated.
    static var versionKey: String { "schedule" }
    static var initialValue: WorkSchedule { WorkSchedule() }
}

extension DatedVersion where Value == WorkSchedule {
    init(from: CalendarDate?, schedule: WorkSchedule) {
        self.init(from: from, value: schedule)
    }

    var schedule: WorkSchedule {
        get { value }
        set { value = newValue }
    }
}

extension DatedHistory where Value == WorkSchedule {
    init() {
        self.init(WorkSchedule())
    }

    /// The week in force on `date`.
    func schedule(on date: CalendarDate) -> WorkSchedule {
        value(on: date)
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

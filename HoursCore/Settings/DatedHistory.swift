import Foundation

/// Something kept with the day it took effect: a contracted week, a rate of
/// pay.
protocol DatedValue: Hashable, Codable, Sendable {
    /// The key a version's value is stored under. The week's is `schedule`,
    /// which is what was written before there was anything else to date.
    static var versionKey: String { get }
    /// What a history holds when a stored list turns out to be empty.
    static var initialValue: Self { get }
}

/// One value, and the day it took effect.
struct DatedVersion<Value: DatedValue>: Hashable, Codable, Sendable {
    /// The first day this value applies to. Nil is "since always": the
    /// version every history starts with.
    var from: CalendarDate?
    var value: Value

    init(from: CalendarDate?, value: Value) {
        self.from = from
        self.value = value
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { self.stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }

        static var from: Key { Key("from") }
        static var value: Key { Key(Value.versionKey) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        self.init(
            from: container.lenientOptional(.from, CalendarDate.self),
            value: container.lenient(.value, Value.initialValue)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encode(value, forKey: .value)
    }
}

/// A value over time, each version with the day it started.
///
/// Contracts change — a four-day week from November, a raise in March — and
/// the months before the change were worked, and possibly handed in, under
/// the old terms. With a single value, saving the new one rewrote every month
/// since the app was installed, closed ones and the running balance included.
/// So a value is kept with the day it started, and everything that reads it
/// for a date reads the version in force on that date: the latest one that
/// had started by then.
///
/// Never empty, sorted by start, and the first version is always "since
/// always", so every date has exactly one answer.
struct DatedHistory<Value: DatedValue>: Hashable, Sendable {
    private(set) var versions: [DatedVersion<Value>]

    init(_ value: Value) {
        self.versions = [DatedVersion(from: nil, value: value)]
    }

    /// Accepts whatever a stored list holds and makes it a history: sorted,
    /// one version per start day (the last one listed wins), and starting
    /// "since always" — a first version with a date would leave the days
    /// before it with no value at all, so it is read as the beginning.
    init(versions: [DatedVersion<Value>]) {
        var byStart: [Int: DatedVersion<Value>] = [:]
        var order: [Int] = []
        for version in versions {
            let key = version.from?.key ?? 0
            if byStart[key] == nil { order.append(key) }
            byStart[key] = version
        }
        var sorted = order.sorted().compactMap { byStart[$0] }
        if sorted.isEmpty { sorted = [DatedVersion(from: nil, value: Value.initialValue)] }
        sorted[0].from = nil
        self.versions = sorted
    }

    /// The value in force on `date`.
    func value(on date: CalendarDate) -> Value {
        versions.last { version in version.from.map { $0 <= date } ?? true }?.value
            ?? versions[0].value
    }

    /// The newest version, which may not have started yet. While there is
    /// one version, it is the value, full stop.
    ///
    /// Setting it edits that version in place without making a new one. That
    /// is what an older version of the app does when it writes `schedule`,
    /// and what someone means when they correct a version rather than change
    /// their contract.
    var latest: Value {
        get { versions[versions.count - 1].value }
        set { versions[versions.count - 1].value = newValue }
    }

    var hasChanges: Bool { versions.count > 1 }

    /// The value is `value` from `date` onward.
    ///
    /// Versions starting on or after `date` are replaced: saving a week from
    /// 16 November says what the week is from then on, and a change planned
    /// for December was a change to the week being replaced. A nil `date` is
    /// "it was always like this", and leaves a single version.
    mutating func change(to value: Value, from date: CalendarDate?) {
        guard let date else {
            versions = [DatedVersion(from: nil, value: value)]
            return
        }
        versions.removeAll { version in version.from.map { $0 >= date } ?? false }
        versions.append(DatedVersion(from: date, value: value))
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

extension DatedHistory: Codable {
    /// Stored as the list of versions alone.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(versions: try container.decode([DatedVersion<Value>].self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(versions)
    }
}

import Foundation

/// A site's usual day and which extras it uses (1.2): the times a new day
/// on the site starts with, the weekdays it is worked, and whether the day
/// asks for the van's kilometres, the evening reminder and the note on the
/// 1st speak about it, and the day shows the diary.
///
/// Kept in settings keyed by the site's id (`AppSettings.siteSetups`) rather
/// than on `Site`: a new attribute on `SiteEntry` means schema V10, a
/// migration stage and a CloudKit schema to deploy again, while V9 is on
/// TestFlight. Settings already travel in every backup and through iCloud's
/// key-value store, decode leniently, and the 1.0 and 1.1 decoders skip a key
/// they do not know. A site with no entry has no usual day and every extra
/// on, which is exactly how every site behaved before this existed.
struct SiteSetup: Hashable, Codable, Sendable {
    /// The usual start and end, both or neither (`hasUsualTimes`).
    var start: TimeOfDay?
    var end: TimeOfDay?
    var breakMinutes: Int
    /// Weekdays the site is worked, 1 = Sunday … 7 = Saturday. Empty means
    /// not set: the reminders then go by the weekdays it was worked lately
    /// (`SiteWorkDays.inferred`).
    var workDays: Set<Int>
    /// The site day has a row for the van's kilometres (while the allowance
    /// is tracked at all).
    var asksKilometres: Bool
    /// The evening "today isn't written" reminder speaks about this site.
    var eveningReminder: Bool
    /// The note on the 1st that last month's sheet is ready.
    var monthlySheet: Bool
    /// The day screen shows the site diary.
    var keepsDiary: Bool

    init(
        start: TimeOfDay? = nil,
        end: TimeOfDay? = nil,
        breakMinutes: Int = 0,
        workDays: Set<Int> = [],
        asksKilometres: Bool = true,
        eveningReminder: Bool = true,
        monthlySheet: Bool = true,
        keepsDiary: Bool = true
    ) {
        self.start = start
        self.end = end
        self.breakMinutes = max(0, breakMinutes)
        self.workDays = workDays.filter { (1...7).contains($0) }
        self.asksKilometres = asksKilometres
        self.eveningReminder = eveningReminder
        self.monthlySheet = monthlySheet
        self.keepsDiary = keepsDiary
    }

    /// Both times are set, so a new day can start with them.
    var hasUsualTimes: Bool { start != nil && end != nil }

    /// Nothing differs from a site that was never set up.
    var isStandard: Bool { self == SiteSetup() }

    private enum CodingKeys: String, CodingKey {
        case start, end, breakMinutes, workDays, asksKilometres, eveningReminder, monthlySheet, keepsDiary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            start: container.lenientOptional(.start),
            end: container.lenientOptional(.end),
            breakMinutes: container.lenient(.breakMinutes, 0),
            workDays: Set(container.lenient(.workDays, [Int]())),
            asksKilometres: container.lenient(.asksKilometres, true),
            eveningReminder: container.lenient(.eveningReminder, true),
            monthlySheet: container.lenient(.monthlySheet, true),
            keepsDiary: container.lenient(.keepsDiary, true)
        )
    }

    /// Only what differs from a site never set up, work days in order.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(start, forKey: .start)
        try container.encodeIfPresent(end, forKey: .end)
        if breakMinutes != 0 { try container.encode(breakMinutes, forKey: .breakMinutes) }
        if !workDays.isEmpty { try container.encode(workDays.sorted(), forKey: .workDays) }
        if !asksKilometres { try container.encode(false, forKey: .asksKilometres) }
        if !eveningReminder { try container.encode(false, forKey: .eveningReminder) }
        if !monthlySheet { try container.encode(false, forKey: .monthlySheet) }
        if !keepsDiary { try container.encode(false, forKey: .keepsDiary) }
    }

    /// Monday to Friday: what a week with no working day falls back to.
    static let mondayToFriday: Set<Int> = [2, 3, 4, 5, 6]
}

/// What a new site starts with (Settings › New sites start with, 1.2): the
/// wizard's "Start fresh" and every other way a site is added. A time or the
/// work days left unset follow the working week (`setup(schedule:)`), so
/// someone who never opens the screen gets their own week's times.
struct NewSiteDefaults: Hashable, Codable, Sendable {
    var start: TimeOfDay?
    var end: TimeOfDay?
    var breakMinutes: Int?
    var workDays: Set<Int>?
    var allowanceByDefault: Bool
    var asksKilometres: Bool
    var eveningReminder: Bool
    var monthlySheet: Bool

    init(
        start: TimeOfDay? = nil,
        end: TimeOfDay? = nil,
        breakMinutes: Int? = nil,
        workDays: Set<Int>? = nil,
        allowanceByDefault: Bool = false,
        asksKilometres: Bool = true,
        eveningReminder: Bool = true,
        monthlySheet: Bool = true
    ) {
        self.start = start
        self.end = end
        self.breakMinutes = breakMinutes.map { max(0, $0) }
        self.workDays = workDays.map { $0.filter { (1...7).contains($0) } }
        self.allowanceByDefault = allowanceByDefault
        self.asksKilometres = asksKilometres
        self.eveningReminder = eveningReminder
        self.monthlySheet = monthlySheet
    }

    /// The setup a new site gets, with the working week filling in what was
    /// not chosen. A week with no working day gives Monday to Friday.
    func setup(schedule: WorkSchedule) -> SiteSetup {
        let weekDays = Set((1...7).filter { schedule.isWorkingWeekday($0) })
        let days = workDays ?? weekDays
        return SiteSetup(
            start: start ?? schedule.defaultStart,
            end: end ?? schedule.defaultEnd,
            breakMinutes: breakMinutes ?? schedule.defaultBreakMinutes,
            workDays: days.isEmpty ? SiteSetup.mondayToFriday : days,
            asksKilometres: asksKilometres,
            eveningReminder: eveningReminder,
            monthlySheet: monthlySheet,
            keepsDiary: true
        )
    }

    private enum CodingKeys: String, CodingKey {
        case start, end, breakMinutes, workDays, allowanceByDefault, asksKilometres, eveningReminder, monthlySheet
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            start: container.lenientOptional(.start),
            end: container.lenientOptional(.end),
            breakMinutes: container.lenientOptional(.breakMinutes),
            workDays: container.lenientOptional(.workDays, [Int].self).map(Set.init),
            allowanceByDefault: container.lenient(.allowanceByDefault, false),
            asksKilometres: container.lenient(.asksKilometres, true),
            eveningReminder: container.lenient(.eveningReminder, true),
            monthlySheet: container.lenient(.monthlySheet, true)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(start, forKey: .start)
        try container.encodeIfPresent(end, forKey: .end)
        try container.encodeIfPresent(breakMinutes, forKey: .breakMinutes)
        try container.encodeIfPresent(workDays?.sorted(), forKey: .workDays)
        if allowanceByDefault { try container.encode(true, forKey: .allowanceByDefault) }
        if !asksKilometres { try container.encode(false, forKey: .asksKilometres) }
        if !eveningReminder { try container.encode(false, forKey: .eveningReminder) }
        if !monthlySheet { try container.encode(false, forKey: .monthlySheet) }
    }
}

extension AppSettings {
    /// A site's usual day and extras; a site never set up has every extra on
    /// and no usual day.
    func siteSetup(for siteID: UUID) -> SiteSetup {
        siteSetups[siteID.uuidString] ?? SiteSetup()
    }

    /// Stores a site's setup. One with nothing in it is not kept, so
    /// settings without any are written exactly as before.
    mutating func setSiteSetup(_ setup: SiteSetup, for siteID: UUID) {
        siteSetups[siteID.uuidString] = setup.isStandard ? nil : setup
    }
}

extension SiteDay {
    /// The day with the site's usual times, when it has no times of its own
    /// yet: what a new day on the site starts with for everyone ticked.
    /// A site with no usual times changes nothing.
    func startingWithUsualTimes(of setup: SiteSetup) -> SiteDay {
        guard setup.hasUsualTimes, start == nil, end == nil else { return self }
        var day = self
        day.start = setup.start
        day.end = setup.end
        day.breakMinutes = setup.breakMinutes
        return day
    }
}

/// Which weekdays a site is worked: its set work days, or else the weekdays
/// it was worked in the last two weeks — the evening reminder's own rule.
enum SiteWorkDays {
    /// How far back "lately" reaches.
    static let lookBackDays = 14

    /// The weekdays `siteID` has days on in the `lookBackDays` before `date`.
    static func inferred(siteID: UUID, siteDays: [SiteDay], before date: CalendarDate, calendar: Calendar) -> Set<Int> {
        let start = date.adding(days: -lookBackDays, in: calendar)
        return Set(
            siteDays
                .filter { $0.siteID == siteID && $0.date >= start && $0.date < date }
                .map { $0.date.weekday(in: calendar) }
        )
    }

    /// The days as runs of consecutive weekdays in the week's own order,
    /// starting at `firstWeekday`, so a screen can say "Mon–Fri" or
    /// "Mon–Wed, Sat". The week does not wrap: Sunday after Saturday joins
    /// the run only when the week starts on Monday.
    static func runs(_ days: Set<Int>, firstWeekday: Int) -> [[Int]] {
        let order = (0..<7).map { ((firstWeekday - 1 + $0) % 7) + 1 }
        var runs: [[Int]] = []
        var current: [Int] = []
        for weekday in order {
            if days.contains(weekday) {
                current.append(weekday)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// The weekdays the site is worked, as of `date`.
    static func weekdays(of siteID: UUID, setup: SiteSetup, siteDays: [SiteDay], before date: CalendarDate, calendar: Calendar) -> Set<Int> {
        setup.workDays.isEmpty ? inferred(siteID: siteID, siteDays: siteDays, before: date, calendar: calendar) : setup.workDays
    }

    /// Whether a day on the site is expected on `date`: one of its weekdays,
    /// and not a public holiday (`holidays`, date keys).
    static func expects(
        _ siteID: UUID,
        on date: CalendarDate,
        setup: SiteSetup,
        siteDays: [SiteDay],
        calendar: Calendar,
        holidays: Set<Int> = []
    ) -> Bool {
        guard !holidays.contains(date.key) else { return false }
        return weekdays(of: siteID, setup: setup, siteDays: siteDays, before: date, calendar: calendar)
            .contains(date.weekday(in: calendar))
    }
}

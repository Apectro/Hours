import Foundation

/// The week the medium widget draws as seven bars.
///
/// Stored with its first day rather than as bare numbers, so the widget can
/// tell after midnight on a Sunday that these are last week's bars and not
/// this week's.
struct WidgetWeek: Codable, Hashable, Sendable {
    var start: CalendarDate
    /// The user's own first weekday, which is not necessarily the phone's.
    var firstWeekday: Int
    /// Seven values, `start` first.
    var workedMinutes: [Int]
    /// The whole week's target. "31:42 of 40:00" reads as how far through the
    /// week you are, which a target cut off at today would not say.
    var expectedMinutes: Int
}

/// One bar of the week as the widget draws it, the running clock included.
struct WidgetWeekBar: Hashable, Sendable {
    var date: CalendarDate
    var minutes: Int
    var isToday: Bool
}

/// One square in the month widget: a working day, and how it went.
struct WidgetDayMark: Codable, Hashable, Sendable {
    enum State: String, Codable, Sendable {
        /// Paid at least what was expected.
        case done
        /// Under what was expected, including nothing recorded at all.
        case short
        case today
        case toCome
    }

    var date: CalendarDate
    var state: State
}

/// The site card: one site, and the last day written up on it.
struct WidgetSite: Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var isTodayWritten: Bool
    /// Today when today is written, otherwise the most recent day before it.
    var lastDay: CalendarDate?
    /// Everyone present that day, you included.
    var lastDayPeople: Int
    /// You are drawn as a face of your own rather than as initials, because
    /// the engine cannot translate "you" and a letter for it would be English.
    var includesYou: Bool
    /// The crew's initials, as many as fit beside you.
    var initials: [String]
    var lastStart: TimeOfDay?
    var lastEnd: TimeOfDay?

    /// People present that day who have no face of their own: the "+3".
    var morePeople: Int {
        max(0, lastDayPeople - initials.count - (includesYou ? 1 : 0))
    }

    init(
        id: UUID,
        name: String,
        isTodayWritten: Bool,
        lastDay: CalendarDate?,
        lastDayPeople: Int,
        includesYou: Bool,
        initials: [String],
        lastStart: TimeOfDay?,
        lastEnd: TimeOfDay?
    ) {
        self.id = id
        self.name = name
        self.isTodayWritten = isTodayWritten
        self.lastDay = lastDay
        self.lastDayPeople = lastDayPeople
        self.includesYou = includesYou
        self.initials = initials
        self.lastStart = lastStart
        self.lastEnd = lastEnd
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isTodayWritten, lastDay, lastDayPeople, includesYou, initials, lastStart, lastEnd
    }

    /// Strict about which site and its name, lenient about the rest. A card
    /// with a made-up identifier would open a site that does not exist, so a
    /// damaged one is better dropped than guessed at.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            isTodayWritten: container.lenient(.isTodayWritten, false),
            lastDay: container.lenientOptional(.lastDay),
            lastDayPeople: container.lenient(.lastDayPeople, 0),
            includesYou: container.lenient(.includesYou, false),
            initials: container.lenient(.initials, []),
            lastStart: container.lenientOptional(.lastStart),
            lastEnd: container.lenientOptional(.lastEnd)
        )
    }
}

/// Works out the redesigned widgets' figures from what the engine has already
/// resolved.
///
/// Nothing here measures a shift or adds up a day. The days arrive as
/// `DayComputation`s from `PeriodEngine`, totals go through `PeriodAggregator`,
/// and a day's state is read from its own balance, so a widget can only ever
/// show what the calendar shows. The app's `WidgetSnapshotWriter` fetches the
/// inputs; this decides what they mean.
enum WidgetSnapshotBuilder {
    /// Faces in a row on the site card before the rest become a count.
    static let maximumFaces = 4

    // MARK: - The week

    /// The week containing `today`, from the calendar's first weekday.
    ///
    /// A day counts towards a bar exactly when it counts towards the app's
    /// own week total, so the bars add up to the figure above them.
    static func week(_ days: [DayComputation], today: CalendarDate, calendar: Calendar) -> WidgetWeek {
        let range = CalendarDateRange.week(containing: today, in: calendar)
        let inWeek = days.filter { range.contains($0.date) }
        let byDate = Dictionary(inWeek.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let worked = range.days(in: calendar).map { date -> Int in
            guard let day = byDate[date], day.counts(through: today) else { return 0 }
            return day.workedMinutes
        }
        return WidgetWeek(
            start: range.start,
            firstWeekday: calendar.firstWeekday,
            workedMinutes: worked,
            expectedMinutes: PeriodAggregator.summarize(inWeek, range: range).expectedMinutes
        )
    }

    // MARK: - The month

    /// A square for every working day of the month, in order.
    ///
    /// Weekends, leave, holidays and time off in lieu are left out rather than drawn as empty:
    /// a row of squares reads as days owed, and none of those are. Nor are
    /// the days before the balance starts.
    static func monthMarks(_ days: [DayComputation], today: CalendarDate) -> [WidgetDayMark] {
        days
            .filter { $0.isIncluded && !$0.precedesBalanceStart && $0.isScheduledWorkingDay && !$0.isTimeOffInLieu }
            .map { day in
                let state: WidgetDayMark.State
                if day.date == today {
                    state = .today
                } else if day.date > today {
                    state = .toCome
                } else {
                    state = day.balanceMinutes < 0 ? .short : .done
                }
                return WidgetDayMark(date: day.date, state: state)
            }
    }

    // MARK: - Earnings

    /// The widgets' earnings, from the summaries the engine already made for
    /// the month and the week through today. Nil unless earnings are what the
    /// app leads with, so a widget never shows money the app does not.
    static func earnings(
        month: EarningsSummary?,
        week: EarningsSummary?,
        today: CalendarDate,
        settings: AppSettings,
        currencyCode: String
    ) -> WidgetEarnings? {
        guard settings.showsEarnings, let month else { return nil }
        return WidgetEarnings(
            currencyCode: currencyCode,
            todayCents: month.days.first { $0.date == today }?.totalCents ?? 0,
            weekCents: week?.totalCents ?? 0,
            monthCents: month.totalCents
        )
    }

    // MARK: - The clock

    /// The site a running clock belongs to, when there is no doubt about it.
    ///
    /// The clock records a job, not a site, so this is the one active site on
    /// that job. Two sites on the same job, or a clock with no job, would make
    /// it a guess, and a widget naming the wrong site is worse than one
    /// naming none.
    static func clockSiteName(for running: RunningShift?, among sites: [Site]) -> String? {
        guard let jobID = running?.jobID else { return nil }
        let matching = sites.filter { !$0.isArchived && $0.jobID == jobID }
        guard matching.count == 1 else { return nil }
        return matching[0].name
    }

    /// When today's work is due to end: the schedule's default end, from the
    /// running clock's job when there is one. Nothing on a day nothing is
    /// expected, where "off at 16:30" would be a strange thing to say.
    static func defaultEnd(today: DayComputation?, running: RunningShift?, settings: AppSettings) -> TimeOfDay? {
        guard let today, today.isIncluded, today.isScheduledWorkingDay, !today.isTimeOffInLieu else { return nil }
        return settings.job(running?.jobID).schedule(on: today.date).defaultEnd
    }

    // MARK: - The site

    /// The active site you worked on most recently.
    ///
    /// "Worked" means you were ticked present. A supervisor who writes the
    /// crew up without ticking themselves falls back to the site written up
    /// most recently, and someone with nothing written yet to their first
    /// site, so a widget is never empty while a site exists. A tie goes to
    /// the site first in the user's order. Archived sites never appear: they
    /// are history, and the widget's buttons are about today.
    static func mostRecentSite(among sites: [Site], recentDays: [SiteDay], today: CalendarDate) -> Site? {
        let active = sites
            .filter { !$0.isArchived }
            .sorted { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) }
        let past = recentDays.filter { $0.date <= today }

        return latest(in: active, days: past.filter { $0.attendance(for: CrewMember.youID) != nil })
            ?? latest(in: active, days: past)
            ?? active.first
    }

    /// The site with the latest of `days`, earlier in `sites` on a tie.
    private static func latest(in sites: [Site], days: [SiteDay]) -> Site? {
        var latest: [UUID: CalendarDate] = [:]
        for day in days {
            latest[day.siteID] = max(latest[day.siteID] ?? day.date, day.date)
        }
        var best: (site: Site, date: CalendarDate)?
        for site in sites {
            guard let date = latest[site.id] else { continue }
            if best == nil || date > best!.date { best = (site, date) }
        }
        return best?.site
    }

    /// The card for `site`. `lastDay` is today's day when it is written,
    /// otherwise the most recent one before it.
    static func site(_ site: Site, today: CalendarDate, lastDay: SiteDay?, crew: [CrewMember]) -> WidgetSite {
        let present = lastDay?.present ?? []
        let includesYou = present.contains { $0.memberID == CrewMember.youID }
        let order = Dictionary(crew.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(crew.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        // In the crew's own order, as the site screen lists them. Someone not
        // on this device's crew list yet, which sync can do for a moment,
        // still has a face; it is just a question mark.
        let others = present
            .filter { $0.memberID != CrewMember.youID }
            .sorted { (order[$0.memberID] ?? .max) < (order[$1.memberID] ?? .max) }
            .map { names[$0.memberID].map(initials(of:)) ?? "?" }

        return WidgetSite(
            id: site.id,
            name: site.name,
            isTodayWritten: lastDay?.date == today,
            lastDay: lastDay?.date,
            lastDayPeople: present.count,
            includesYou: includesYou,
            initials: Array(others.prefix(maximumFaces - (includesYou ? 1 : 0))),
            lastStart: lastDay?.start,
            lastEnd: lastDay?.end
        )
    }

    /// "Ivan Horvat" → "IH": the first and last names' first letters, or one
    /// letter for a single name. A middle name would make three, which does
    /// not fit in a face the size of a fingertip.
    static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first else { return "?" }
        guard words.count > 1, let last = words.last?.first else {
            return String(first).uppercased()
        }
        return String(first).uppercased() + String(last).uppercased()
    }
}

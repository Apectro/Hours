import Foundation

// The 1.2 widgets' figures: the week day by day, the month as dots, the
// balance as days off, leave, what the month earned and the site's crew.
//
// Everything a widget decides is decided here, from days `PeriodEngine` has
// already resolved, so it is tested on Linux with the rest of the engine and
// the widget extension only draws. The types are carried in `WidgetSnapshot`,
// each one optional or empty in a file an earlier version wrote.

// MARK: - The week, day by day

/// One day of the week as the widgets draw it: a bar, a row of the week list.
struct WidgetWeekDay: Codable, Hashable, Sendable {
    /// What kind of day it is, as far as a bar or a row needs to know.
    enum Kind: String, Codable, Sendable {
        /// A working day, or any day with hours worked on it.
        case work
        /// Vacation, time off in lieu, or another paid absence.
        case leave
        case sick
        case holiday
        /// A weekend or any other day nothing is expected on.
        case off
    }

    var date: CalendarDate
    var kind: Kind
    /// Worked, credited and the balance as the app counts them, so nothing
    /// for a day still to come or a day left out of totals.
    var workedMinutes: Int
    var creditedMinutes: Int
    var balanceMinutes: Int
    /// What the day expects, known ahead of the day: past midnight the widget
    /// can still tell whether the new day is a working day.
    var expectedMinutes: Int
    var start: TimeOfDay?
    var end: TimeOfDay?
    /// The day type's name, already in the phone's language, for a day that
    /// is not plain work: "Vacation", "Sick leave", a holiday's own name.
    var typeName: String?
    /// When work usually starts, from the week in force that day. Nil on a
    /// day nobody is due at work.
    var usualStart: TimeOfDay?

    /// Worked plus credited: what the day pays.
    var paidMinutes: Int { workedMinutes + creditedMinutes }

    init(
        date: CalendarDate,
        kind: Kind,
        workedMinutes: Int = 0,
        creditedMinutes: Int = 0,
        balanceMinutes: Int = 0,
        expectedMinutes: Int = 0,
        start: TimeOfDay? = nil,
        end: TimeOfDay? = nil,
        typeName: String? = nil,
        usualStart: TimeOfDay? = nil
    ) {
        self.date = date
        self.kind = kind
        self.workedMinutes = workedMinutes
        self.creditedMinutes = creditedMinutes
        self.balanceMinutes = balanceMinutes
        self.expectedMinutes = expectedMinutes
        self.start = start
        self.end = end
        self.typeName = typeName
        self.usualStart = usualStart
    }

    private enum CodingKeys: String, CodingKey {
        case date, kind, workedMinutes, creditedMinutes, balanceMinutes, expectedMinutes
        case start, end, typeName, usualStart
    }

    /// Strict about the date, which places the day; lenient about the rest.
    /// A kind a later version adds reads as a quiet day rather than costing
    /// the whole week.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind: String = container.lenient(.kind, Kind.off.rawValue)
        self.init(
            date: try container.decode(CalendarDate.self, forKey: .date),
            kind: Kind(rawValue: kind) ?? .off,
            workedMinutes: container.lenient(.workedMinutes, 0),
            creditedMinutes: container.lenient(.creditedMinutes, 0),
            balanceMinutes: container.lenient(.balanceMinutes, 0),
            expectedMinutes: container.lenient(.expectedMinutes, 0),
            start: container.lenientOptional(.start, TimeOfDay.self),
            end: container.lenientOptional(.end, TimeOfDay.self),
            typeName: container.lenientOptional(.typeName, String.self),
            usualStart: container.lenientOptional(.usualStart, TimeOfDay.self)
        )
    }
}

/// One row of the week list at the moment it is drawn.
struct WidgetWeekRow: Hashable, Sendable {
    var day: WidgetWeekDay
    /// Today's with the running clock in it.
    var paidMinutes: Int
    var balanceMinutes: Int
    var isToday: Bool
    var isFuture: Bool
    var isRunning: Bool
}

/// One bar of the week chart.
struct WidgetWeekColumn: Hashable, Sendable {
    enum Style: Hashable, Sendable {
        /// Hours worked: a filled bar.
        case worked
        /// Credited absence: an outlined bar at the hours it credits.
        case leave
        /// Today, the running clock included.
        case today
        /// Nothing: a short track.
        case empty
    }

    var date: CalendarDate
    var minutes: Int
    var style: Style
    /// The bar's height as a share of the chart's.
    var fraction: Double
    var isToday: Bool
    var isRunning: Bool
}

/// The week as bars, with the line a normal day reaches.
struct WidgetWeekChart: Hashable, Sendable {
    var columns: [WidgetWeekColumn]
    /// Where the dashed target line sits, or nil with no working day to
    /// measure by.
    var targetFraction: Double?
    /// Worked and credited this week, today's running clock included.
    var paidMinutes: Int
    /// The whole week's target.
    var expectedMinutes: Int
    /// The week's balance through today, today counted as it stands.
    var balanceMinutes: Int

    /// Ten hours fill a bar, unless a longer day needs more room.
    static let fullScaleMinutes = 600
}

// MARK: - Today

/// Which of its three faces the Today widget shows.
enum WidgetTodayState: Hashable, Sendable {
    /// The clock is running: the figure, and Stop.
    case running(since: Date)
    /// Not running on a day that is, or may be, a working day: the figure,
    /// when work usually starts, and Start.
    case idle(usualStart: TimeOfDay?)
    /// Nothing expected and nothing worked: "Day off" and the week.
    case dayOff
}

// MARK: - The month as dots

/// One day of the month calendar.
struct WidgetMonthDay: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// A filled dot.
        case worked
        /// A ring: vacation, time off in lieu, paid absence — taken or booked.
        case leave
        /// A dashed ring.
        case sick
        /// A small dot: a weekend, a holiday, a day before the balance starts.
        case off
        /// A past working day with nothing on it.
        case missing
        /// An empty disc: a working day still to come.
        case future
        case today
    }

    var date: CalendarDate
    var kind: Kind

    init(date: CalendarDate, kind: Kind) {
        self.date = date
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey { case date, kind }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind: String = container.lenient(.kind, Kind.off.rawValue)
        self.init(date: try container.decode(CalendarDate.self, forKey: .date), kind: Kind(rawValue: kind) ?? .off)
    }
}

// MARK: - Leave

/// Where the leave year stands, for the Leave widget.
struct WidgetLeave: Codable, Hashable, Sendable {
    var leaveYear: Int
    /// What the year gives plus what was carried in and has not expired.
    var available: HalfDays
    var taken: HalfDays
    var booked: HalfDays
    /// The next stretch of leave after today, weekends inside it included.
    var nextStart: CalendarDate?
    var nextEnd: CalendarDate?

    var remaining: HalfDays { available - taken - booked }

    /// The ring: what is left of what is available, between nothing and all.
    var remainingFraction: Double {
        guard available.halves > 0 else { return 0 }
        return min(max(Double(remaining.halves) / Double(available.halves), 0), 1)
    }

    init(
        leaveYear: Int,
        available: HalfDays,
        taken: HalfDays,
        booked: HalfDays,
        nextStart: CalendarDate? = nil,
        nextEnd: CalendarDate? = nil
    ) {
        self.leaveYear = leaveYear
        self.available = available
        self.taken = taken
        self.booked = booked
        self.nextStart = nextStart
        self.nextEnd = nextEnd
    }

    private enum CodingKeys: String, CodingKey {
        case leaveYear, availableHalves, takenHalves, bookedHalves, nextStart, nextEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            leaveYear: try container.decode(Int.self, forKey: .leaveYear),
            available: HalfDays(halves: container.lenient(.availableHalves, 0)),
            taken: HalfDays(halves: container.lenient(.takenHalves, 0)),
            booked: HalfDays(halves: container.lenient(.bookedHalves, 0)),
            nextStart: container.lenientOptional(.nextStart, CalendarDate.self),
            nextEnd: container.lenientOptional(.nextEnd, CalendarDate.self)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(leaveYear, forKey: .leaveYear)
        try container.encode(available.halves, forKey: .availableHalves)
        try container.encode(taken.halves, forKey: .takenHalves)
        try container.encode(booked.halves, forKey: .bookedHalves)
        try container.encodeIfPresent(nextStart, forKey: .nextStart)
        try container.encodeIfPresent(nextEnd, forKey: .nextEnd)
    }
}

// MARK: - What the month earned

/// The month's earnings and what they are made of, for the Earned widget.
///
/// Present whenever a rate is set, whichever figure the app leads with: the
/// Earned widget is a choice made by placing it.
struct WidgetMonthEarned: Codable, Hashable, Sendable {
    var year: Int
    var month: Int
    var currencyCode: String
    /// What the hours earned, surcharges and paid absence included.
    var hoursCents: Int
    /// Worked and credited, the hours behind `hoursCents`.
    var paidMinutes: Int
    var allowanceDays: Int
    var allowanceCents: Int
    var kilometres: Int
    var mileageCents: Int

    var totalCents: Int { hoursCents + allowanceCents + mileageCents }

    /// The lines under the figure, each only when it has something in it.
    var rows: [WidgetEarnedRow] {
        var rows: [WidgetEarnedRow] = []
        if hoursCents != 0 { rows.append(WidgetEarnedRow(kind: .hours(paidMinutes), cents: hoursCents)) }
        if allowanceDays > 0 { rows.append(WidgetEarnedRow(kind: .allowance(allowanceDays), cents: allowanceCents)) }
        if kilometres > 0 { rows.append(WidgetEarnedRow(kind: .kilometres(kilometres), cents: mileageCents)) }
        return rows
    }

    init(
        year: Int,
        month: Int,
        currencyCode: String,
        hoursCents: Int = 0,
        paidMinutes: Int = 0,
        allowanceDays: Int = 0,
        allowanceCents: Int = 0,
        kilometres: Int = 0,
        mileageCents: Int = 0
    ) {
        self.year = year
        self.month = month
        self.currencyCode = currencyCode
        self.hoursCents = hoursCents
        self.paidMinutes = paidMinutes
        self.allowanceDays = allowanceDays
        self.allowanceCents = allowanceCents
        self.kilometres = kilometres
        self.mileageCents = mileageCents
    }

    private enum CodingKeys: String, CodingKey {
        case year, month, currencyCode, hoursCents, paidMinutes, allowanceDays, allowanceCents, kilometres, mileageCents
    }

    /// Strict about the month and the currency, which a guess would get
    /// wrong, and lenient about the figures.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            year: try container.decode(Int.self, forKey: .year),
            month: try container.decode(Int.self, forKey: .month),
            currencyCode: try container.decode(String.self, forKey: .currencyCode),
            hoursCents: container.lenient(.hoursCents, 0),
            paidMinutes: container.lenient(.paidMinutes, 0),
            allowanceDays: container.lenient(.allowanceDays, 0),
            allowanceCents: container.lenient(.allowanceCents, 0),
            kilometres: container.lenient(.kilometres, 0),
            mileageCents: container.lenient(.mileageCents, 0)
        )
    }
}

/// One line of the Earned widget.
struct WidgetEarnedRow: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// The hours, in minutes.
        case hours(Int)
        /// Days with the field allowance.
        case allowance(Int)
        case kilometres(Int)
    }

    var kind: Kind
    var cents: Int
}

// MARK: - The site's crew

/// One person on the site widget's list: here, or why not.
struct WidgetCrewRow: Codable, Hashable, Sendable {
    var name: String
    var isPresent: Bool
    /// Why they are away, already in the phone's language. Nil for someone
    /// present, or away with no reason given.
    var reason: String?

    init(name: String, isPresent: Bool, reason: String?) {
        self.name = name
        self.isPresent = isPresent
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey { case name, isPresent, reason }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: container.lenient(.name, ""),
            isPresent: container.lenient(.isPresent, false),
            reason: container.lenientOptional(.reason, String.self)
        )
    }

    /// The rows that fit in `lines`, and how many more there are. When they
    /// do not all fit, the last line says "+3 more" instead of a name.
    static func fitting(_ rows: [WidgetCrewRow], lines: Int) -> (rows: [WidgetCrewRow], more: Int) {
        guard rows.count > lines else { return (rows, 0) }
        let shown = max(0, lines - 1)
        return (Array(rows.prefix(shown)), rows.count - shown)
    }
}

extension WidgetSite {
    /// Everyone ticked present on the card's day.
    var presentCount: Int { crew.filter(\.isPresent).count }
}

// MARK: - Half days

extension HalfDays {
    /// "1½", "½", "2": the way days off are said on a widget.
    var withHalfSign: String {
        let sign = halves < 0 ? "-" : ""
        let magnitude = abs(halves)
        let whole = magnitude / 2
        guard magnitude % 2 == 1 else { return sign + String(whole) }
        return sign + (whole == 0 ? "" : String(whole)) + "½"
    }
}

// MARK: - Building them

extension WidgetSnapshotBuilder {
    /// What kind of day this is for a bar or a row.
    static func kind(of day: DayComputation) -> WidgetWeekDay.Kind {
        switch day.dayType.id {
        case .sick: return .sick
        case .holiday: return .holiday
        case .vacation, .timeOffInLieu: return .leave
        default: break
        }
        if day.workedMinutes > 0 || day.isScheduledWorkingDay { return .work }
        if day.dayType.expectation == .creditedAbsence { return .leave }
        return .off
    }

    /// The week containing `today`, day by day, from the calendar's first
    /// weekday. A day's figures are there exactly when the day counts towards
    /// the app's own week total.
    static func weekDays(
        _ days: [DayComputation],
        today: CalendarDate,
        settings: AppSettings,
        calendar: Calendar,
        language: ExportLanguage = .device
    ) -> [WidgetWeekDay] {
        let range = CalendarDateRange.week(containing: today, in: calendar)
        let byDate = Dictionary(
            days.filter { range.contains($0.date) }.map { ($0.date, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return range.days(in: calendar).map { date in
            guard let day = byDate[date] else { return WidgetWeekDay(date: date, kind: .off) }
            let counts = day.counts(through: today)
            let kind = kind(of: day)
            let isDue = day.isIncluded && !day.precedesBalanceStart
            return WidgetWeekDay(
                date: date,
                kind: kind,
                workedMinutes: counts ? day.workedMinutes : 0,
                creditedMinutes: counts ? day.creditedMinutes : 0,
                balanceMinutes: counts ? day.balanceMinutes : 0,
                expectedMinutes: isDue ? day.expectedMinutes : 0,
                start: day.start,
                end: day.end,
                typeName: typeName(of: day, kind: kind, language: language),
                usualStart: day.isScheduledWorkingDay && !day.isTimeOffInLieu
                    ? settings.job(nil).schedule(on: date).defaultStart
                    : nil
            )
        }
    }

    private static func typeName(of day: DayComputation, kind: WidgetWeekDay.Kind, language: ExportLanguage) -> String? {
        switch kind {
        case .work, .off: return nil
        case .holiday: return day.holidayName ?? day.dayType.displayName(in: language)
        case .leave, .sick: return day.dayType.displayName(in: language)
        }
    }

    /// A dot for every day of the month, in order.
    static func monthDays(_ days: [DayComputation], today: CalendarDate) -> [WidgetMonthDay] {
        days.map { day in WidgetMonthDay(date: day.date, kind: dot(for: day, today: today)) }
    }

    private static func dot(for day: DayComputation, today: CalendarDate) -> WidgetMonthDay.Kind {
        if day.date == today { return .today }
        guard day.isIncluded, !day.precedesBalanceStart else { return .off }
        switch kind(of: day) {
        case .sick: return .sick
        case .leave: return .leave
        case .holiday, .off: return day.workedMinutes > 0 && day.date < today ? .worked : .off
        case .work:
            if day.date > today { return day.isScheduledWorkingDay ? .future : .off }
            return day.workedMinutes > 0 ? .worked : .missing
        }
    }

    /// The running balance, while the app keeps one. With "Calculate
    /// overtime" off there is no balance, and the widget says so rather than
    /// showing a zero.
    static func totalBalance(_ minutes: Int, settings: AppSettings) -> Int? {
        settings.features.showsBalance ? minutes : nil
    }

    /// The balance as days off at the average working day, to the nearest
    /// half — nil when there is nothing to take.
    static func daysOff(balanceMinutes: Int, on date: CalendarDate, settings: AppSettings) -> HalfDays? {
        guard let days = OvertimeAvailable(balanceMinutes: balanceMinutes, on: date, settings: settings)?.daysOff,
              days > .zero else { return nil }
        return days
    }

    /// The leave year for the widget, or nil for someone who has never
    /// mentioned leave — the same rule Insights uses to show its card.
    static func leave(
        balance: LeaveBalance,
        days: [DayComputation],
        settings: AppSettings,
        today: CalendarDate,
        calendar: Calendar
    ) -> WidgetLeave? {
        let inUse = settings.leave.isCustomized || balance.used > .zero || balance.planned > .zero || balance.carried > .zero
        guard inUse else { return nil }
        let next = nextLeave(in: days, after: today)
        return WidgetLeave(
            leaveYear: balance.leaveYear,
            available: balance.allowance + balance.carried - balance.expired,
            taken: balance.used,
            booked: balance.planned,
            nextStart: next?.start,
            nextEnd: next?.end
        )
    }

    /// The first stretch of vacation that starts after today. Days nothing
    /// is expected on — a weekend, a holiday — do not break a stretch, so a
    /// week off from Friday to Friday is one; a working day does. A stretch
    /// already under way is not "next".
    static func nextLeave(in days: [DayComputation], after today: CalendarDate) -> CalendarDateRange? {
        var start: CalendarDate?
        var end: CalendarDate?
        for day in days.sorted(by: { $0.date < $1.date }) {
            let isLeave = day.isIncluded && day.dayType.id == .vacation
            if isLeave {
                if start == nil { start = day.date }
                end = day.date
            } else if day.isScheduledWorkingDay || day.workedMinutes > 0 {
                if let start, let end, start > today { return CalendarDateRange(start: start, end: end) }
                start = nil
                end = nil
            }
        }
        if let start, let end, start > today { return CalendarDateRange(start: start, end: end) }
        return nil
    }

    /// The month through today and what it is made of; nil without a rate.
    static func monthEarned(
        summary: EarningsSummary?,
        days: [DayComputation],
        settings: AppSettings,
        today: CalendarDate,
        currencyCode: String
    ) -> WidgetMonthEarned? {
        guard let summary else { return nil }
        let month = today.yearMonth
        let inMonth = days.filter { $0.date.yearMonth == month }
        let allowance = AllowanceSummary(days: inMonth, settings: settings, countingThrough: today)
        let paid = inMonth
            .filter { EarningsSummary.counts($0, through: today) }
            .reduce(0) { $0 + $1.paidMinutes }
        return WidgetMonthEarned(
            year: month.year,
            month: month.month,
            currencyCode: currencyCode,
            hoursCents: summary.breakdown.hoursCents,
            paidMinutes: paid,
            allowanceDays: allowance.allowanceDays,
            allowanceCents: summary.breakdown.allowanceCents,
            kilometres: allowance.kilometres,
            mileageCents: summary.breakdown.mileageCents
        )
    }

    /// The site day's people: everyone ticked present first — you, then the
    /// crew in their own order — then those away with the reason given, then
    /// the rest of the crew nobody has marked. Hidden members appear only
    /// when the day names them.
    static func crew(
        day: SiteDay?,
        crew: [CrewMember],
        catalog: DayTypeCatalog,
        siteNames: [UUID: String],
        language: ExportLanguage = .device
    ) -> [WidgetCrewRow] {
        guard let day else { return [] }
        let ordered = crew.enumerated()
            .sorted { ($0.element.sortOrder, $0.offset) < ($1.element.sortOrder, $1.offset) }
            .map(\.element)
        let people: [(id: UUID, name: String, isHidden: Bool)] =
            [(CrewMember.youID, language(.you), true)] + ordered.map { ($0.id, $0.name, $0.isHidden) }

        func reasonText(_ reason: AbsenceReason) -> String {
            switch reason {
            case let .dayType(id): return catalog.definition(for: id).displayName(in: language)
            case let .otherSite(siteID): return siteID.flatMap { siteNames[$0] } ?? language(.otherSite)
            }
        }

        var present: [WidgetCrewRow] = []
        var away: [WidgetCrewRow] = []
        var unmarked: [WidgetCrewRow] = []
        for person in people {
            if day.attendance(for: person.id) != nil {
                present.append(WidgetCrewRow(name: person.name, isPresent: true, reason: nil))
            } else if let reason = day.absenceReason(for: person.id) {
                away.append(WidgetCrewRow(name: person.name, isPresent: false, reason: reasonText(reason)))
            } else if !person.isHidden {
                unmarked.append(WidgetCrewRow(name: person.name, isPresent: false, reason: nil))
            }
        }
        return present + away + unmarked
    }

    /// A site's name short enough for a circular Lock Screen widget:
    /// "Trg Pravde" → "TP", "Hauptstraße 12" → "H 12". A short name is kept.
    static func shortName(of name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 5 else { return trimmed }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        let numbers = words.filter { $0.first?.isNumber ?? false }
        let letters = words
            .filter { !($0.first?.isNumber ?? true) }
            .compactMap { $0.first.map { String($0).uppercased() } }
        let initials = letters.prefix(3).joined()
        guard let number = numbers.first else { return initials }
        return initials.isEmpty ? String(number) : initials + " " + number
    }
}

// MARK: - At the moment of drawing

extension WidgetSnapshot {
    /// The week's days as they stand at `instant`, today's with the running
    /// clock in it. Nil once the week is over, or in a file without them.
    func weekRows(at instant: Date, calendar: Calendar) -> [WidgetWeekRow]? {
        guard weekDays.count == 7 else { return nil }
        let today = CalendarDate.today(in: calendar, now: instant)
        guard weekDays.contains(where: { $0.date == today }) else { return nil }
        let sameDay = describesDay(of: instant, calendar: calendar)
        let running = runningMinutes(at: instant)

        return weekDays.map { day in
            let isToday = day.date == today
            guard isToday else {
                return WidgetWeekRow(
                    day: day, paidMinutes: day.paidMinutes, balanceMinutes: day.balanceMinutes,
                    isToday: false, isFuture: day.date > today, isRunning: false
                )
            }
            // Past midnight the stored day is the new day as the file saw it
            // yesterday — nothing on it yet — so only its target is known.
            let paid = (sameDay ? day.paidMinutes : 0) + running
            let balance = (sameDay ? day.balanceMinutes : -day.expectedMinutes) + running
            return WidgetWeekRow(
                day: day, paidMinutes: paid, balanceMinutes: balance,
                isToday: true, isFuture: false, isRunning: isClockRunning && clockStartedAt != nil
            )
        }
    }

    /// The week as bars at `instant`.
    func weekChart(at instant: Date, calendar: Calendar) -> WidgetWeekChart? {
        guard let rows = weekRows(at: instant, calendar: calendar) else { return nil }
        let today = CalendarDate.today(in: calendar, now: instant)

        let shaped: [(row: WidgetWeekRow, style: WidgetWeekColumn.Style, minutes: Int)] = rows.map { row in
            if row.isToday { return (row, .today, row.paidMinutes) }
            if row.day.workedMinutes > 0 { return (row, .worked, row.paidMinutes) }
            if row.day.creditedMinutes > 0 { return (row, .leave, row.day.creditedMinutes) }
            return (row, .empty, 0)
        }
        let target = averageDayMinutes > 0 ? averageDayMinutes : (weekDays.map(\.expectedMinutes).max() ?? 0)
        let scale = Double(max(WidgetWeekChart.fullScaleMinutes, shaped.map(\.minutes).max() ?? 0, target))

        return WidgetWeekChart(
            columns: shaped.map { item in
                WidgetWeekColumn(
                    date: item.row.day.date,
                    minutes: item.minutes,
                    style: item.style,
                    fraction: Double(item.minutes) / scale,
                    isToday: item.row.isToday,
                    isRunning: item.row.isRunning
                )
            },
            targetFraction: target > 0 ? Double(target) / scale : nil,
            paidMinutes: rows.reduce(0) { $0 + $1.paidMinutes },
            expectedMinutes: weekDays.reduce(0) { $0 + $1.expectedMinutes },
            balanceMinutes: rows.filter { $0.day.date <= today }.reduce(0) { $0 + $1.balanceMinutes }
        )
    }

    /// Which face the Today widget shows at `instant`.
    ///
    /// Past midnight the file still describes yesterday, but its week knows
    /// what the new day expects, so a Saturday morning reads as a day off
    /// before the app has run. In a week the file knows nothing about,
    /// nothing is assumed.
    func todayState(at instant: Date, calendar: Calendar) -> WidgetTodayState {
        if isClockRunning, let clockStartedAt { return .running(since: clockStartedAt) }
        let today = CalendarDate.today(in: calendar, now: instant)
        let day = weekDays.first { $0.date == today }
        let worked = todayIncludingRunningClock(at: instant, calendar: calendar)

        let expected: Int? = describesDay(of: instant, calendar: calendar) ? todayExpectedMinutes : day?.expectedMinutes
        let isAway = day.map { [WidgetWeekDay.Kind.leave, .sick, .holiday].contains($0.kind) } ?? false
        let isOff = expected == 0 || isAway
        if worked == 0, expected != nil, isOff { return .dayOff }
        return .idle(usualStart: day?.usualStart)
    }

    /// The month's dots at `instant`. Past midnight the dot that was today
    /// takes yesterday's own figures and the new day becomes today.
    func monthDays(at instant: Date, calendar: Calendar) -> [WidgetMonthDay] {
        guard describesMonth(of: instant, calendar: calendar) else { return [] }
        guard !describesDay(of: instant, calendar: calendar) else { return monthDays }

        let today = CalendarDate.today(in: calendar, now: instant)
        let yesterday: WidgetMonthDay.Kind = todayWorkedMinutes > 0
            ? .worked
            : (todayExpectedMinutes > 0 ? .missing : .off)
        return monthDays.map { day in
            var day = day
            if day.date == today {
                day.kind = .today
            } else if day.kind == .today, day.date < today {
                day.kind = yesterday
            }
            return day
        }
    }

    /// The month's earnings at `instant`: nothing yet in a month the file
    /// does not describe, though a rate is still set.
    func monthEarned(at instant: Date, calendar: Calendar) -> WidgetMonthEarned? {
        guard let monthEarned else { return nil }
        guard !describesMonth(of: instant, calendar: calendar) else { return monthEarned }
        let month = CalendarDate.today(in: calendar, now: instant).yearMonth
        return WidgetMonthEarned(year: month.year, month: month.month, currencyCode: monthEarned.currencyCode)
    }

    /// The running balance at `instant`, while the app keeps one. Not moved
    /// by the running clock: the balance changes when the shift is saved,
    /// as it does in the app.
    var showsTotalBalance: Bool { totalBalanceMinutes != nil }
}

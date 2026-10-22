import Foundation

/// A day of the year with no year attached: when a leave year starts, when
/// carried-over leave runs out.
struct MonthDay: Hashable, Codable, Sendable {
    var month: Int
    var day: Int

    init(month: Int, day: Int) {
        self.month = min(max(month, 1), 12)
        self.day = min(max(day, 1), 31)
    }

    /// This day in `year`. A day the month does not have — 29 February in a
    /// common year, 31 April typed by hand — is the month's last day, so a
    /// leave year always starts somewhere rather than nowhere.
    func date(in year: Int, calendar: Calendar) -> CalendarDate {
        let month = YearMonth(year: year, month: self.month)
        return CalendarDate(year: year, month: self.month, day: min(day, month.dayCount(in: calendar)))
    }

    private enum CodingKeys: String, CodingKey { case month, day }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            month: try container.decode(Int.self, forKey: .month),
            day: try container.decode(Int.self, forKey: .day)
        )
    }
}

/// The vacation allowance, for the primary job.
///
/// Days rather than hours, because that is how a contract states it and how
/// people count it: "25 days", "18 left". Halves are allowed — a part-time
/// contract can give 22½ — and the engine counts in whole halves
/// (`HalfDays`), so no figure here is ever 17.4999.
///
/// Settings written before this existed read as the defaults; nothing
/// shows until somebody takes a vacation day or changes the policy (see
/// `isInUse`).
struct LeavePolicy: Hashable, Codable, Sendable {
    /// Days of vacation each leave year gives. Austria commonly 25 or 30,
    /// Germany 20 to 30.
    var allowanceDays: Double
    /// The first day of a leave year. A leave year is named for the calendar
    /// year it starts in.
    var yearStart: MonthDay
    /// Days carried over from the leave year before `carriedOverYear`.
    var carriedOverDays: Double
    /// The leave year the carry-over was entered for. Stored with it so that
    /// last year's figure is not quietly carried into every year after; nil
    /// reads as no carry-over at all.
    var carriedOverYear: Int?
    /// When carried-over leave not taken by then is lost, if it is — often
    /// 31 March. Nil means it is kept all year.
    var carryOverExpires: MonthDay?

    init(
        allowanceDays: Double = 25,
        yearStart: MonthDay = MonthDay(month: 1, day: 1),
        carriedOverDays: Double = 0,
        carriedOverYear: Int? = nil,
        carryOverExpires: MonthDay? = nil
    ) {
        self.allowanceDays = max(0, allowanceDays)
        self.yearStart = yearStart
        self.carriedOverDays = max(0, carriedOverDays)
        self.carriedOverYear = carriedOverYear
        self.carryOverExpires = carryOverExpires
    }

    /// Whether anybody has told the app anything about their leave.
    var isCustomized: Bool { self != LeavePolicy() }

    /// The leave year `date` falls in, named for the year it started.
    func leaveYear(containing date: CalendarDate, calendar: Calendar) -> Int {
        date < yearStart.date(in: date.year, calendar: calendar) ? date.year - 1 : date.year
    }

    /// From the start of `leaveYear` to the day before the next one starts.
    func range(ofLeaveYear leaveYear: Int, calendar: Calendar) -> CalendarDateRange {
        CalendarDateRange(
            start: yearStart.date(in: leaveYear, calendar: calendar),
            end: yearStart.date(in: leaveYear + 1, calendar: calendar).adding(days: -1, in: calendar)
        )
    }

    /// Days carried into `leaveYear`: the figure entered, only for the year
    /// it was entered for.
    func carriedOver(into leaveYear: Int) -> Double {
        carriedOverYear == leaveYear ? carriedOverDays : 0
    }

    /// The day carried-over leave runs out in `leaveYear`: the first time
    /// the expiry date comes round on or after the year's start.
    func carryOverExpiry(inLeaveYear leaveYear: Int, calendar: Calendar) -> CalendarDate? {
        guard let carryOverExpires else { return nil }
        let start = yearStart.date(in: leaveYear, calendar: calendar)
        let sameYear = carryOverExpires.date(in: leaveYear, calendar: calendar)
        return sameYear >= start ? sameYear : carryOverExpires.date(in: leaveYear + 1, calendar: calendar)
    }

    private enum CodingKeys: String, CodingKey {
        case allowanceDays, yearStart, carriedOverDays, carriedOverYear, carryOverExpires
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LeavePolicy()
        self.init(
            allowanceDays: container.lenient(.allowanceDays, defaults.allowanceDays),
            yearStart: container.lenient(.yearStart, defaults.yearStart),
            carriedOverDays: container.lenient(.carriedOverDays, defaults.carriedOverDays),
            carriedOverYear: container.lenientOptional(.carriedOverYear, Int.self),
            carryOverExpires: container.lenientOptional(.carryOverExpires, MonthDay.self)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(allowanceDays, forKey: .allowanceDays)
        try container.encode(yearStart, forKey: .yearStart)
        try container.encode(carriedOverDays, forKey: .carriedOverDays)
        try container.encodeIfPresent(carriedOverYear, forKey: .carriedOverYear)
        try container.encodeIfPresent(carryOverExpires, forKey: .carryOverExpires)
    }
}

import Foundation

/// A number of days counted in halves.
///
/// Leave is taken in whole and half days, so it is counted that way: an
/// integer of halves can be added and compared exactly, and written as
/// "17" or "17.5" without a floating-point remainder ever reaching a screen.
struct HalfDays: Hashable, Comparable, Sendable {
    var halves: Int

    init(halves: Int) { self.halves = halves }

    /// The nearest half day.
    init(days: Double) { self.halves = Int((days * 2).rounded()) }

    var days: Double { Double(halves) / 2 }

    /// "17", "17.5", "-1.5": no trailing zero, and the separator the reader
    /// expects. The engine cannot ask the locale on every platform it builds
    /// on, so the app says which.
    func formatted(decimalSeparator: String = ".") -> String {
        let sign = halves < 0 ? "-" : ""
        let magnitude = abs(halves)
        let whole = String(magnitude / 2)
        return sign + (magnitude % 2 == 0 ? whole : whole + decimalSeparator + "5")
    }

    static func + (lhs: HalfDays, rhs: HalfDays) -> HalfDays { HalfDays(halves: lhs.halves + rhs.halves) }
    static func - (lhs: HalfDays, rhs: HalfDays) -> HalfDays { HalfDays(halves: lhs.halves - rhs.halves) }
    static func < (lhs: HalfDays, rhs: HalfDays) -> Bool { lhs.halves < rhs.halves }
    static let zero = HalfDays(halves: 0)
}

/// Where a leave year stands.
struct LeaveBalance: Hashable, Sendable {
    var leaveYear: Int
    var range: CalendarDateRange
    /// What the year gives.
    var allowance: HalfDays
    /// Brought in from the year before.
    var carried: HalfDays
    /// Vacation days on or before today.
    var used: HalfDays
    /// Vacation days already entered after today.
    var planned: HalfDays
    /// Carried-over days lost because they were not taken by the expiry.
    var expired: HalfDays
    /// When carried-over days run out this year, if they do.
    var carryOverExpiry: CalendarDate?
    /// Carried-over days that will be lost unless more leave goes in before
    /// the expiry. Zero once it has passed — they are `expired` then.
    var carryOverAtRisk: HalfDays

    /// What is left to book. Planned days are already spoken for.
    var remaining: HalfDays { allowance + carried - expired - used - planned }
}

/// Counts vacation days against a `LeavePolicy`.
///
/// Reads days `PeriodEngine` has already resolved and never looks at a
/// record, so a vacation day here is exactly the vacation day the calendar
/// and the month total show.
enum LeaveCalculator {
    /// How much leave one day takes, in halves.
    ///
    /// Only the built-in Vacation type takes leave — sick days, holidays and
    /// time off in lieu come out of something else. A day nothing is
    /// contracted on (a Saturday, a non-working weekday) takes none, and nor
    /// does an excluded day.
    ///
    /// The app has no half-day type. What it does have is a vacation day whose
    /// expected hours were set lower by hand, which credits fewer hours: such
    /// a day is half a day of leave when it credits up to half of what the
    /// week in force contracts, and a whole one above that. Credited nothing,
    /// it takes nothing. Where expected hours are not tracked, or the user has
    /// made Vacation an uncredited type, every vacation day on a working day
    /// is a whole one.
    static func halfDays(for day: DayComputation, settings: AppSettings, calendar: Calendar) -> Int {
        guard day.dayType.id == .vacation, day.isIncluded else { return 0 }
        let contracted = settings.contractedMinutes(on: day.date, calendar: calendar)
        guard contracted > 0 else { return 0 }
        guard settings.features.trackExpectedHours, day.dayType.expectation != .zero else { return 2 }
        let expected = day.expectedMinutes
        if expected <= 0 { return 0 }
        return expected * 2 <= contracted ? 1 : 2
    }

    /// The balance of `leaveYear` as of `today`.
    ///
    /// Carried-over days are spent first, in date order, as an employer
    /// counts them: leave taken or booked on or before the expiry uses up
    /// carry-over before it touches the year's own allowance. Whatever
    /// carry-over is left the day after the expiry is gone.
    ///
    /// - Parameter days: the resolved days of the leave year. Days outside it
    ///   are ignored.
    static func balance(
        leaveYear: Int,
        days: [DayComputation],
        settings: AppSettings,
        calendar: Calendar,
        today: CalendarDate
    ) -> LeaveBalance {
        let policy = settings.leave
        let range = policy.range(ofLeaveYear: leaveYear, calendar: calendar)
        let expiry = policy.carryOverExpiry(inLeaveYear: leaveYear, calendar: calendar)
        let carried = HalfDays(days: policy.carriedOver(into: leaveYear))

        var used = 0
        var planned = 0
        var byExpiry = 0
        for day in days where range.contains(day.date) {
            let halves = halfDays(for: day, settings: settings, calendar: calendar)
            guard halves > 0 else { continue }
            if day.date <= today { used += halves } else { planned += halves }
            if let expiry, day.date <= expiry { byExpiry += halves }
        }

        var expired = HalfDays.zero
        var atRisk = HalfDays.zero
        if let expiry {
            let unspent = HalfDays(halves: max(0, carried.halves - byExpiry))
            if today > expiry { expired = unspent } else { atRisk = unspent }
        }

        return LeaveBalance(
            leaveYear: leaveYear,
            range: range,
            allowance: HalfDays(days: policy.allowanceDays),
            carried: carried,
            used: HalfDays(halves: used),
            planned: HalfDays(halves: planned),
            expired: expired,
            carryOverExpiry: expiry,
            carryOverAtRisk: atRisk
        )
    }
}

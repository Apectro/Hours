import Foundation

/// "Your 2026": a year's figures for the review cards.
///
/// Read from the calculators Insights uses — `PeriodEngine` for the days and
/// the earnings, `PeriodAggregator` for the totals, `BalanceLedger` for the
/// months, `LeaveCalculator` for leave — and from nothing else, so no card can
/// say something the Insights screen for the same year contradicts.
///
/// One difference, on purpose: the year stops at today. Insights counts a day
/// already entered for next week, because booked leave is owed hours; a
/// review of what the year was does not, the same way earnings do not.
///
/// Personal only. Site days reach it as your own shifts in your own calendar,
/// and nothing about anybody else's hours — or anybody's money but yours —
/// is an input.
struct YearReview: Hashable, Sendable {
    /// The cards, in the order they are shown. One without anything to say is
    /// left out.
    enum Card: String, CaseIterable, Hashable, Sendable {
        case hours, sites, busiestMonth, longestDay, balance, vacation, earnings, badWeather
    }

    struct SiteVisits: Hashable, Sendable {
        var siteID: UUID
        var name: String
        var days: Int
    }

    struct MonthTotal: Hashable, Sendable {
        var month: YearMonth
        var workedMinutes: Int
    }

    struct DayTotal: Hashable, Sendable {
        var date: CalendarDate
        var workedMinutes: Int
    }

    /// The bad-weather day type, by id rather than by a `DayTypeID` constant:
    /// the type ships separately, and this has to work with or without it —
    /// as a built-in, a custom type of that id, or not at all.
    static let badWeatherTypeID = DayTypeID("badWeather")

    var year: Int
    var workedMinutes: Int
    var daysWorked: Int
    /// Days with a shift written from a site day.
    var daysOnSites: Int
    /// The site with the most of them that still has a name.
    var topSite: SiteVisits?
    var busiestMonth: MonthTotal?
    var longestDay: DayTotal?
    /// The year's own balance: its days, not the running total.
    var balanceMinutes: Int
    var overtimeMinutes: Int
    /// Leave taken, counted as `LeaveCalculator` counts it.
    var vacationDays: HalfDays
    /// What you earned, when a job has a rate.
    var earningsCents: Int?
    /// Nil when there is no bad-weather type or no day of it.
    var badWeatherDays: Int?

    /// Nothing worked and nothing recorded: the year has no review, only a
    /// friendly word.
    var isEmpty: Bool
    /// How many sites a shift was written from, deleted ones too: "on 4
    /// sites", on the first card (1.2).
    var sitesWorked: Int = 0

    var cards: [Card] {
        guard !isEmpty else { return [] }
        return Card.allCases.filter { card in
            switch card {
            case .hours, .balance: return true
            case .sites: return daysOnSites > 0
            case .busiestMonth: return busiestMonth != nil
            case .longestDay: return longestDay != nil
            case .vacation: return vacationDays > .zero
            case .earnings: return (earningsCents ?? 0) > 0
            case .badWeather: return badWeatherDays != nil
            }
        }
    }

    /// - Parameters:
    ///   - records: the stored days, covering the year's whole weeks
    ///     (`engine.earningsRange(covering:)`), which earnings need.
    ///   - siteNames: every site's name, archived ones included; a site not
    ///     in it has been deleted and is not named.
    static func make(
        year: Int,
        engine: PeriodEngine,
        records: [Int: DayRecord],
        holidays: [HolidayRule],
        today: CalendarDate,
        siteNames: [UUID: String]
    ) -> YearReview {
        let calendar = engine.calendar
        let settings = engine.settings
        let range = CalendarDateRange.year(year, in: calendar)
        let throughToday = engine.days(in: range, records: records, holidays: holidays)
            .filter { $0.date <= today }
        let summary = PeriodAggregator.summarize(throughToday, range: range, countingThrough: today)
        let counted = throughToday.filter { $0.counts(through: today) }

        // Sites: a day counts once per site, however many shifts it had there.
        var siteDays: [UUID: Int] = [:]
        var daysOnSites = 0
        for day in counted {
            let sites = Set(day.shifts.compactMap(\.siteID))
            if !sites.isEmpty { daysOnSites += 1 }
            for site in sites { siteDays[site, default: 0] += 1 }
        }
        let topSite = siteDays
            .compactMap { id, days in siteNames[id].map { SiteVisits(siteID: id, name: $0, days: days) } }
            .max { ($0.days, $1.name) < ($1.days, $0.name) }

        let months = BalanceLedger.monthlySeries(
            over: throughToday, openingMinutes: 0, startDate: nil, countingThrough: today
        )
        let busiest = months
            .filter { $0.workedMinutes > 0 }
            .max { ($0.workedMinutes, $1.month) < ($1.workedMinutes, $0.month) }
            .map { MonthTotal(month: $0.month, workedMinutes: $0.workedMinutes) }

        let longest = counted
            .filter { $0.workedMinutes > 0 }
            .max { ($0.workedMinutes, $1.date) < ($1.workedMinutes, $0.date) }
            .map { DayTotal(date: $0.date, workedMinutes: $0.workedMinutes) }

        let vacation = counted.reduce(0) { $0 + LeaveCalculator.halfDays(for: $1, settings: settings, calendar: calendar) }

        let hasBadWeatherType = settings.dayTypeCatalog.all.contains { $0.id == badWeatherTypeID }
        let badWeather = summary.count(of: badWeatherTypeID)

        let earnings = engine.earnings(in: range, records: records, holidays: holidays, countingThrough: today)

        return YearReview(
            year: year,
            workedMinutes: summary.workedMinutes,
            daysWorked: summary.daysWorked,
            daysOnSites: daysOnSites,
            topSite: topSite,
            busiestMonth: busiest,
            longestDay: longest,
            balanceMinutes: summary.balanceMinutes,
            overtimeMinutes: summary.overtimeMinutes,
            vacationDays: HalfDays(halves: vacation),
            earningsCents: earnings?.totalCents,
            badWeatherDays: hasBadWeatherType && badWeather > 0 ? badWeather : nil,
            isEmpty: summary.workedMinutes == 0 && summary.daysWithEntries == 0,
            sitesWorked: siteDays.count
        )
    }

    /// The year the late-December card offers, if any: from the 20th to the
    /// end of the month, until it has been opened or put away for that year.
    /// Never pushed — it only waits on the Insights screen.
    static func yearToOffer(today: CalendarDate, dismissedYear: Int?) -> Int? {
        guard today.month == 12, today.day >= 20, dismissedYear != today.year else { return nil }
        return today.year
    }
}

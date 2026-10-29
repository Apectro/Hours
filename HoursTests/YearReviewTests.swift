import XCTest
@testable import Hours

/// "Your 2025": the year's figures, checked against a year worked out by hand.
final class YearReviewTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let siteA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let siteB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    private let today = Fixture.date(2026, 1, 10)
    private let badWeather = DayTypeDefinition(
        id: DayTypeID("badWeather"), name: "Bad weather", symbolName: "cloud.rain", tint: .gray,
        expectation: .creditedAbsence, showsTimesByDefault: false
    )

    private func worked(
        _ date: CalendarDate, _ start: Int, _ end: Int, endMinute: Int = 0, site: UUID? = nil
    ) -> DayRecord {
        DayRecord(date: date, shifts: [
            Shift(
                id: site ?? UUID(),
                start: Fixture.time(start), end: Fixture.time(end, endMinute),
                breaks: [BreakSpan.duration(30)],
                siteID: site
            )
        ])
    }

    /// Worked: 10h (site A), 8h (site A), 8h (site B) in March, 12h in June.
    /// Two and a half days of vacation in August, one day of bad weather in
    /// October.
    private var records: [Int: DayRecord] {
        let list = [
            worked(Fixture.date(2025, 3, 3), 7, 17, endMinute: 30, site: siteA),
            worked(Fixture.date(2025, 3, 4), 8, 16, endMinute: 30, site: siteA),
            worked(Fixture.date(2025, 3, 5), 8, 16, endMinute: 30, site: siteB),
            worked(Fixture.date(2025, 6, 2), 6, 18, endMinute: 30),
            DayRecord(date: Fixture.date(2025, 8, 4), dayTypeID: .vacation),
            DayRecord(date: Fixture.date(2025, 8, 5), dayTypeID: .vacation),
            DayRecord(date: Fixture.date(2025, 8, 6), dayTypeID: .vacation, expectedOverrideMinutes: 240),
            DayRecord(date: Fixture.date(2025, 10, 1), dayTypeID: DayTypeID("badWeather"))
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.date.key, $0) })
    }

    private func review(
        _ records: [Int: DayRecord],
        settings: AppSettings? = nil,
        firstRecorded: CalendarDate? = Fixture.date(2025, 3, 3)
    ) -> YearReview {
        let settings = settings ?? Fixture.settings(customDayTypes: [badWeather])
        let engine = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: firstRecorded)
        return YearReview.make(
            year: 2025, engine: engine, records: records, holidays: [], today: today,
            siteNames: [siteA: "Hauptstraße 12", siteB: "Bahnhof"]
        )
    }

    func testTheFiguresMatchTheYearWorkedOutByHand() {
        let review = review(records)
        XCTAssertFalse(review.isEmpty)
        XCTAssertEqual(review.year, 2025)
        XCTAssertEqual(review.workedMinutes, 600 + 480 + 480 + 720)
        XCTAssertEqual(review.daysWorked, 4)
        XCTAssertEqual(review.daysOnSites, 3)
        XCTAssertEqual(review.topSite, YearReview.SiteVisits(siteID: siteA, name: "Hauptstraße 12", days: 2))
        XCTAssertEqual(review.busiestMonth, YearReview.MonthTotal(month: YearMonth(year: 2025, month: 3), workedMinutes: 1560))
        XCTAssertEqual(review.longestDay, YearReview.DayTotal(date: Fixture.date(2025, 6, 2), workedMinutes: 720))
        XCTAssertEqual(review.vacationDays, HalfDays(halves: 5))
        XCTAssertEqual(review.badWeatherDays, 1)
        XCTAssertNil(review.earningsCents, "no rate, no money")
    }

    /// 218 weekdays from 3 March to 31 December 2025. Eight have something on
    /// them; the other 210 are each a day short. 10h on an 8h day is +2h, and
    /// 12h is +4h; leave and bad weather are credited and cost nothing.
    func testTheBalanceIsTheYearsOwn() {
        let review = review(records)
        XCTAssertEqual(review.balanceMinutes, 120 + 240 - 210 * 480)
        XCTAssertEqual(review.overtimeMinutes, 360)
    }

    func testItReadsTheSameCalculatorsAsInsights() {
        let settings = Fixture.settings(customDayTypes: [badWeather])
        let engine = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: Fixture.date(2025, 3, 3))
        let year = CalendarDateRange.year(2025, in: calendar)
        let summary = engine.summary(in: year, records: records, holidays: [], countingThrough: today)
        let review = review(records, settings: settings)
        XCTAssertEqual(review.workedMinutes, summary.workedMinutes)
        XCTAssertEqual(review.balanceMinutes, summary.balanceMinutes)
        XCTAssertEqual(review.daysWorked, summary.daysWorked)
    }

    func testEarningsAppearOnlyWithARate() {
        var settings = Fixture.settings(customDayTypes: [badWeather])
        settings.changePay(forJob: Job.primaryID, to: PayRules(hourlyRateCents: 20_00), from: nil)
        let review = review(records, settings: settings)
        // 38h worked and 28h credited (two days and a half of leave, a day of
        // bad weather) at €20.
        XCTAssertEqual(review.earningsCents, (38 + 28) * 20_00)
    }

    func testWithoutABadWeatherTypeThereIsNoBadWeatherCard() {
        var plain = records
        plain.removeValue(forKey: Fixture.date(2025, 10, 1).key)
        let review = review(plain, settings: Fixture.settings())
        XCTAssertNil(review.badWeatherDays)
        XCTAssertFalse(review.cards.contains(.badWeather))
    }

    func testABadWeatherTypeWithNoDaysShowsNoCard() {
        var plain = records
        plain.removeValue(forKey: Fixture.date(2025, 10, 1).key)
        XCTAssertNil(review(plain).badWeatherDays)
    }

    /// "On 2 sites", for the first card (1.2): every site worked on, named
    /// or not.
    func testItCountsTheSitesWorkedOn() {
        XCTAssertEqual(review(records).sitesWorked, 2)
        XCTAssertEqual(review([:]).sitesWorked, 0)
    }

    func testTheCardsAreTheOnesWithSomethingToSay() {
        XCTAssertEqual(review(records).cards, [.hours, .sites, .busiestMonth, .longestDay, .balance, .vacation, .badWeather])

        let onlyJune = [Fixture.date(2025, 6, 2).key: worked(Fixture.date(2025, 6, 2), 8, 16, endMinute: 30)]
        XCTAssertEqual(
            review(onlyJune, firstRecorded: Fixture.date(2025, 6, 2)).cards,
            [.hours, .busiestMonth, .longestDay, .balance]
        )
    }

    func testAYearWithNothingInItIsEmpty() {
        let review = review([:], firstRecorded: nil)
        XCTAssertTrue(review.isEmpty)
        XCTAssertEqual(review.workedMinutes, 0)
        XCTAssertNil(review.topSite)
        XCTAssertNil(review.busiestMonth)
        XCTAssertNil(review.longestDay)
        XCTAssertEqual(review.vacationDays, .zero)
        XCTAssertEqual(review.cards, [])
    }

    func testAYearBeforeAnythingWasRecordedIsEmptyToo() {
        let review = review(records, firstRecorded: Fixture.date(2025, 3, 3))
        let earlier = YearReview.make(
            year: 2024,
            engine: PeriodEngine(settings: Fixture.settings(), calendar: calendar, firstRecorded: Fixture.date(2025, 3, 3)),
            records: records, holidays: [], today: today, siteNames: [:]
        )
        XCTAssertFalse(review.isEmpty)
        XCTAssertTrue(earlier.isEmpty, "a year of days before the balance started is not a year of days short")
    }

    func testTheYearInProgressStopsAtToday() {
        let midYear = Fixture.date(2025, 6, 1)
        let engine = PeriodEngine(settings: Fixture.settings(customDayTypes: [badWeather]), calendar: calendar, firstRecorded: Fixture.date(2025, 3, 3))
        let review = YearReview.make(year: 2025, engine: engine, records: records, holidays: [], today: midYear, siteNames: [:])
        XCTAssertEqual(review.workedMinutes, 1560, "June's day is still to come")
        XCTAssertEqual(review.vacationDays, .zero, "booked leave is not leave taken")
    }

    func testASiteSinceDeletedIsNotNamed() {
        let review = YearReview.make(
            year: 2025,
            engine: PeriodEngine(settings: Fixture.settings(customDayTypes: [badWeather]), calendar: calendar, firstRecorded: Fixture.date(2025, 3, 3)),
            records: records, holidays: [], today: today, siteNames: [siteB: "Bahnhof"]
        )
        XCTAssertEqual(review.daysOnSites, 3)
        XCTAssertEqual(review.topSite?.name, "Bahnhof", "the most-visited site that still has a name")
    }

    // MARK: - The December card

    func testTheCardIsOfferedInLateDecemberUntilDismissed() {
        XCTAssertNil(YearReview.yearToOffer(today: Fixture.date(2026, 12, 19), dismissedYear: nil))
        XCTAssertEqual(YearReview.yearToOffer(today: Fixture.date(2026, 12, 20), dismissedYear: nil), 2026)
        XCTAssertEqual(YearReview.yearToOffer(today: Fixture.date(2026, 12, 31), dismissedYear: 2025), 2026)
        XCTAssertNil(YearReview.yearToOffer(today: Fixture.date(2026, 12, 24), dismissedYear: 2026))
        XCTAssertNil(YearReview.yearToOffer(today: Fixture.date(2027, 1, 2), dismissedYear: nil))
    }
}

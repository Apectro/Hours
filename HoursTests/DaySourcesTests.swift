import XCTest
@testable import Hours

/// Where a day's hours came from (2026-11-24): the month grid's bar, its
/// filter chips and "Sites 112h · Own 16h 30m" are the day's own worked
/// minutes, cut by site and own.
final class DaySourcesTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let date = Fixture.workingTuesday
    private let here = UUID()
    private let there = UUID()

    private func time(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    private func siteShift(_ site: UUID, _ start: TimeOfDay, _ end: TimeOfDay, breakMinutes: Int = 0) -> Shift {
        Shift(
            id: site,
            start: start,
            end: end,
            breaks: breakMinutes > 0 ? [BreakSpan(id: site, explicitMinutes: breakMinutes)] : [],
            siteID: site
        )
    }

    private func day(
        _ shifts: [Shift],
        on date: CalendarDate? = nil,
        settings: AppSettings = Fixture.settings(),
        configure: (inout DayRecord) -> Void = { _ in }
    ) -> DayComputation {
        var record = DayRecord(date: date ?? self.date, shifts: shifts)
        configure(&record)
        return WorkdayCalculator(settings: settings, calendar: calendar).compute(record: record, on: record.date)
    }

    // MARK: - One day

    func testATwoSiteDayHasBothInTheOrderWorked() {
        let sources = DaySources.make(day([
            siteShift(there, time(12, 30), time(15, 30)),
            siteShift(here, time(7), time(12))
        ]))
        XCTAssertEqual(sources.sites, [.init(siteID: here, minutes: 300), .init(siteID: there, minutes: 180)])
        XCTAssertEqual(sources.ownMinutes, 0)
        XCTAssertEqual(sources.totalMinutes, 480)
    }

    func testASiteDayPlusOwnHours() {
        let computed = day([
            siteShift(here, time(7), time(12)),
            Shift(start: time(16), end: time(17, 30))
        ])
        let sources = DaySources.make(computed)
        XCTAssertEqual(sources.sites, [.init(siteID: here, minutes: 300)])
        XCTAssertEqual(sources.ownMinutes, 90)
        XCTAssertEqual(sources.totalMinutes, computed.workedMinutes)
        XCTAssertEqual(sources.minutes(for: .all), 390)
        XCTAssertEqual(sources.minutes(for: .site(here)), 300)
        XCTAssertEqual(sources.minutes(for: .site(there)), 0)
        XCTAssertEqual(sources.minutes(for: .own), 90)
    }

    func testADayOfYourOwnHasNoSite() {
        let sources = DaySources.make(day([Shift(start: time(8), end: time(16, 30), breaks: [.duration(30)])]))
        XCTAssertTrue(sources.sites.isEmpty)
        XCTAssertEqual(sources.ownMinutes, 480)
    }

    func testNothingWorkedIsEmpty() {
        XCTAssertTrue(DaySources.make(day([])).isEmpty)
        XCTAssertTrue(DaySources.make(.empty(on: date)).isEmpty)
    }

    func testOwnHoursOverASiteCountOnceAndTheSiteKeepsThem() {
        // 11:30–12:30 of your own against 07:00–12:00 on the site: the
        // shared half hour is the site's.
        let computed = day([
            siteShift(here, time(7), time(12)),
            Shift(start: time(11, 30), end: time(12, 30))
        ])
        let sources = DaySources.make(computed)
        XCTAssertEqual(sources.minutes(on: here), 300)
        XCTAssertEqual(sources.ownMinutes, 30)
        XCTAssertEqual(sources.totalMinutes, computed.workedMinutes)
    }

    func testRoundingGoesToYourOwnHoursWhenThereAreSome() {
        let settings = Fixture.settings(rounding: .nearestQuarterHour)
        let computed = day([
            siteShift(here, time(7), time(12)),
            Shift(start: time(16), end: time(17, 25))
        ], settings: settings)
        let sources = DaySources.make(computed)
        XCTAssertEqual(computed.workedMinutes, 390, "385 rounded to the quarter hour")
        XCTAssertEqual(sources.minutes(on: here), 300)
        XCTAssertEqual(sources.ownMinutes, 90)
    }

    func testRoundingGoesToTheLastSiteWhenNothingIsYourOwn() {
        let settings = Fixture.settings(rounding: .nearestQuarterHour)
        let computed = day([
            siteShift(here, time(7), time(11)),
            siteShift(there, time(12), time(15, 25))
        ], settings: settings)
        let sources = DaySources.make(computed)
        XCTAssertEqual(computed.workedMinutes, 450)
        XCTAssertEqual(sources.sites, [.init(siteID: here, minutes: 240), .init(siteID: there, minutes: 210)])
        XCTAssertEqual(sources.ownMinutes, 0)
    }

    func testATypedInFigureWithNoShiftsIsYourOwn() {
        var features = FeatureToggles()
        features.autoCalculateWorkedHours = false
        let computed = day([], settings: Fixture.settings(features: features)) { $0.manualWorkedMinutes = 420 }
        let sources = DaySources.make(computed)
        XCTAssertEqual(sources.ownMinutes, 420)
        XCTAssertTrue(sources.sites.isEmpty)
    }

    func testTheSourcesAlwaysAddUpToTheDay() {
        let settings = Fixture.settings(rounding: .nearestQuarterHour)
        let cases: [[Shift]] = [
            [siteShift(here, time(7), time(11, 50))],
            [siteShift(here, time(7), time(11, 50)), siteShift(there, time(12), time(12, 10))],
            [siteShift(here, time(7), time(7, 10)), Shift(start: time(8), end: time(8, 10))],
            [Shift(start: time(22), end: time(2))],
        ]
        for shifts in cases {
            let computed = day(shifts, settings: settings)
            XCTAssertEqual(DaySources.make(computed).totalMinutes, computed.workedMinutes)
        }
    }

    // MARK: - A period and its filter

    /// Monday on one site, Tuesday on two with an hour of your own,
    /// Wednesday your own only.
    private var week: [DayComputation] {
        [
            day([siteShift(here, time(7), time(15), breakMinutes: 30)], on: Fixture.date(2026, 8, 3)),
            day([
                siteShift(here, time(7), time(12)),
                siteShift(there, time(12, 30), time(15, 30)),
                Shift(start: time(16), end: time(17))
            ], on: Fixture.date(2026, 8, 4)),
            day([Shift(start: time(8), end: time(12))], on: Fixture.date(2026, 8, 5)),
            day([], on: Fixture.date(2026, 8, 6)),
        ]
    }

    func testAPeriodAddsUpBySiteAndOwn() {
        let sources = PeriodSources(days: week)
        XCTAssertEqual(sources.minutesBySite, [here: 450 + 300, there: 180])
        XCTAssertEqual(sources.siteMinutes, 930)
        XCTAssertEqual(sources.ownMinutes, 60 + 240)
        XCTAssertEqual(sources.totalMinutes, week.reduce(0) { $0 + $1.workedMinutes })
        XCTAssertNil(sources.days[Fixture.date(2026, 8, 6).key], "a day with no hours has no bar")
    }

    func testAFiltersTotals() {
        let sources = PeriodSources(days: week)
        XCTAssertEqual(sources.minutes(for: .all), 1_230)
        XCTAssertEqual(sources.minutes(for: .site(here)), 750)
        XCTAssertEqual(sources.minutes(for: .site(there)), 180)
        XCTAssertEqual(sources.minutes(for: .own), 300)
        XCTAssertEqual(
            sources.minutes(for: .site(here)) + sources.minutes(for: .site(there)) + sources.minutes(for: .own),
            sources.minutes(for: .all),
            "the filters are a cut of the total, nothing counted twice"
        )
        XCTAssertEqual(sources.days[Fixture.date(2026, 8, 4).key]?.minutes(for: .site(there)), 180)
        XCTAssertEqual(sources.days[Fixture.date(2026, 8, 3).key]?.minutes(for: .own), 0)
    }

    func testAPeriodCountsWhatTheSummaryCounts() {
        var days = week
        days[0].isIncluded = false
        let sources = PeriodSources(days: days, countingThrough: Fixture.date(2026, 8, 4))
        let summary = PeriodAggregator.summarize(
            days,
            range: CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 6)),
            countingThrough: Fixture.date(2026, 8, 4)
        )
        XCTAssertEqual(sources.totalMinutes, summary.workedMinutes)
    }

    func testTheChipsAreAllThenActiveSitesWithHoursThenOwn() {
        let sources = PeriodSources(days: week)
        let idle = Site(name: "Idle", sortOrder: 0)
        let archived = Site(id: there, name: "Trg Pravde", isArchived: true, sortOrder: 1)
        let active = Site(id: here, name: "Jarunski Dvori", sortOrder: 2)

        XCTAssertEqual(sources.filters(sites: []), [], "no site at all: no row of chips")
        XCTAssertEqual(
            sources.filters(sites: [active, archived, idle]),
            [.all, .site(here), .own],
            "a site with no hours in the period, or archived, gets no chip"
        )
        var both = archived
        both.isArchived = false
        XCTAssertEqual(sources.filters(sites: [active, both]), [.all, .site(there), .site(here), .own], "in the sites' order")
    }

    func testAFilterWithNoChipFallsBackToAll() {
        let sources = PeriodSources(days: week)
        let active = Site(id: here, name: "Jarunski Dvori")
        XCTAssertEqual(sources.effective(.site(here), sites: [active]), .site(here))
        XCTAssertEqual(sources.effective(.site(there), sites: [active]), .all)
        XCTAssertEqual(sources.effective(.own, sites: [active]), .own)
        XCTAssertEqual(sources.effective(.own, sites: []), .all)
    }

    func testWeekTotalsFollowTheFilter() {
        let layout = MonthLayout.week(containing: Fixture.date(2026, 8, 4), calendar: calendar, includesWeekends: true)
        let all = PeriodSources.weekMinutes(of: layout, days: week, calendar: calendar, countingThrough: nil, filter: .all)
        XCTAssertEqual(all, CalendarWeekTotals.minutes(of: layout, days: week, calendar: calendar, countingThrough: nil))
        XCTAssertEqual(
            PeriodSources.weekMinutes(of: layout, days: week, calendar: calendar, countingThrough: nil, filter: .site(here)),
            [750]
        )
        XCTAssertEqual(
            PeriodSources.weekMinutes(of: layout, days: week, calendar: calendar, countingThrough: nil, filter: .own),
            [300]
        )
    }

    // MARK: - A colour per site

    func testASitesColourIsItsPlaceAmongAllSites() {
        let first = Site(id: here, name: "A", sortOrder: 0)
        let second = Site(id: there, name: "B", sortOrder: 1)
        XCTAssertEqual(SitePalette.indexes(of: [second, first]), [here: 0, there: 1], "whatever order they were fetched in")
    }

    func testArchivingASiteDoesNotMoveTheOthers() {
        var first = Site(id: here, name: "A", sortOrder: 0)
        let second = Site(id: there, name: "B", sortOrder: 1)
        let before = SitePalette.indexes(of: [first, second])
        first.isArchived = true
        XCTAssertEqual(SitePalette.indexes(of: [first, second]), before)
    }

    func testTheColoursGoRoundThePalette() {
        let sites = (0..<(SitePalette.count + 2)).map { Site(name: "S\($0)", sortOrder: $0) }
        let indexes = SitePalette.indexes(of: sites)
        XCTAssertEqual(sites.map { indexes[$0.id] }, (0..<(SitePalette.count + 2)).map { $0 % SitePalette.count })
        XCTAssertEqual(Set(indexes.values.prefix(SitePalette.count)).count <= SitePalette.count, true)
    }

    func testSitesWithTheSameSortOrderStillGetAStableOrder() {
        let one = Site(name: "A", sortOrder: 0)
        let two = Site(name: "B", sortOrder: 0)
        XCTAssertEqual(SitePalette.indexes(of: [one, two]), SitePalette.indexes(of: [two, one]))
        XCTAssertNotEqual(SitePalette.indexes(of: [one, two])[one.id], SitePalette.indexes(of: [one, two])[two.id])
    }

    func testASiteNoLongerStoredStillHasOneColour() {
        let index = SitePalette.fallbackIndex(for: here)
        XCTAssertEqual(index, SitePalette.fallbackIndex(for: here))
        XCTAssertTrue((0..<SitePalette.count).contains(index))
    }
}

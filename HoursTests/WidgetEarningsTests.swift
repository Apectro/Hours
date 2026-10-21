import XCTest
@testable import Hours

/// Earnings in the widgets: the same engine as the app, carried in the
/// snapshot, and only when they are what the app leads with.
final class WidgetEarningsTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// Thursday 6 August 2026. The week runs Monday 3 to Sunday 9.
    private let thursday = Fixture.date(2026, 8, 6)

    private func settings(rate: Int? = 15_00, mainFigure: MainFigure = .earnings) -> AppSettings {
        var settings = Fixture.settings()
        if let rate { settings.changePay(forJob: Job.primaryID, to: PayRules(hourlyRateCents: rate), from: nil) }
        settings.mainFigure = mainFigure
        return settings
    }

    private func worked(_ day: Int, month: Int = 8) -> DayRecord {
        DayRecord(date: Fixture.date(2026, month, day), start: Fixture.time(8), end: Fixture.time(16))
    }

    private func earnings(_ settings: AppSettings, records: [DayRecord]) -> WidgetEarnings? {
        let engine = Fixture.engine(settings: settings, calendar: calendar)
        let byKey = Dictionary(records.map { ($0.date.key, $0) }, uniquingKeysWith: { first, _ in first })
        let month = engine.earnings(
            in: YearMonth(year: 2026, month: 8).range(in: calendar),
            records: byKey, holidays: [], countingThrough: thursday
        )
        let week = engine.earnings(
            in: CalendarDateRange.week(containing: thursday, in: calendar),
            records: byKey, holidays: [], countingThrough: thursday
        )
        return WidgetSnapshotBuilder.earnings(
            month: month, week: week, today: thursday, settings: settings, currencyCode: "EUR"
        )
    }

    private func noon(on date: CalendarDate) -> Date {
        date.date(in: calendar)
    }

    func testTheWidgetCarriesTodayTheWeekAndTheMonth() {
        let result = earnings(settings(), records: [worked(31, month: 7), worked(3), worked(4), worked(6), worked(7)])

        XCTAssertEqual(result?.todayCents, 120_00)
        XCTAssertEqual(result?.weekCents, 360_00, "Monday, Tuesday and today; Friday has not happened")
        XCTAssertEqual(result?.monthCents, 360_00)
        XCTAssertEqual(result?.currencyCode, "EUR")
    }

    func testNoRateMeansNoEarnings() {
        XCTAssertNil(earnings(settings(rate: nil), records: [worked(6)]))
    }

    func testTheHoursBalanceChosenMeansNoEarnings() {
        XCTAssertNil(earnings(settings(mainFigure: .hoursBalance), records: [worked(6)]))
    }

    func testEarningsDoNotOutliveTheirDayWeekOrMonth() {
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = noon(on: thursday)
        snapshot.week = WidgetSnapshotBuilder.week([], today: thursday, calendar: calendar)
        snapshot.earnings = WidgetEarnings(currencyCode: "EUR", todayCents: 100, weekCents: 200, monthCents: 300)

        XCTAssertEqual(snapshot.todayEarnings(at: noon(on: thursday), calendar: calendar), 100)
        XCTAssertEqual(snapshot.todayEarnings(at: noon(on: Fixture.date(2026, 8, 7)), calendar: calendar), 0)
        XCTAssertEqual(snapshot.weekEarnings(at: noon(on: Fixture.date(2026, 8, 9)), calendar: calendar), 200)
        XCTAssertEqual(snapshot.weekEarnings(at: noon(on: Fixture.date(2026, 8, 10)), calendar: calendar), 0)
        XCTAssertEqual(snapshot.monthEarnings(at: noon(on: Fixture.date(2026, 8, 31)), calendar: calendar), 300)
        XCTAssertEqual(snapshot.monthEarnings(at: noon(on: Fixture.date(2026, 9, 1)), calendar: calendar), 0)
    }

    func testASnapshotWithoutEarningsShowsHours() {
        let snapshot = WidgetSnapshot.empty

        XCTAssertFalse(snapshot.showsEarnings)
        XCTAssertNil(snapshot.todayEarnings(at: noon(on: thursday), calendar: calendar))
    }

    func testAnOlderFileHasNoEarnings() throws {
        let json = Data(#"{"todayWorkedMinutes": 90, "showsBalance": true}"#.utf8)

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: json)

        XCTAssertNil(decoded.earnings)
        XCTAssertFalse(decoded.showsEarnings)
    }

    func testEarningsSurviveARoundTrip() throws {
        var snapshot = WidgetSnapshot.empty
        snapshot.earnings = WidgetEarnings(currencyCode: "CHF", todayCents: 1, weekCents: 2, monthCents: 3)

        let data = try JSONEncoder().encode(snapshot)

        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: data), snapshot)
    }
}

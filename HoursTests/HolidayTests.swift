import XCTest
@testable import Hours

/// Holiday recurrence. No country is assumed, so all of this is about rules
/// the user wrote themselves behaving predictably.
final class HolidayTests: XCTestCase {
    private let calendar = Fixture.calendar()

    func testAnAnnualHolidayRepeatsEveryYear() {
        let recurrence = HolidayRecurrence.annual(month: 12, day: 25)
        XCTAssertEqual(recurrence.occurrence(inYear: 2026, calendar: calendar), Fixture.date(2026, 12, 25))
        XCTAssertEqual(recurrence.occurrence(inYear: 2030, calendar: calendar), Fixture.date(2030, 12, 25))
    }

    func testAOneOffHolidayOccursInItsOwnYearOnly() {
        let recurrence = HolidayRecurrence.once(on: Fixture.date(2026, 1, 1))
        XCTAssertEqual(recurrence.occurrence(inYear: 2026, calendar: calendar), Fixture.date(2026, 1, 1))
        XCTAssertNil(recurrence.occurrence(inYear: 2027, calendar: calendar))
    }

    func testTheFourthThursdayInNovember() {
        let recurrence = HolidayRecurrence.nthWeekday(ordinal: 4, weekday: 5, month: 11)
        XCTAssertEqual(recurrence.occurrence(inYear: 2026, calendar: calendar), Fixture.date(2026, 11, 26))
    }

    func testTheLastMondayInMay() {
        let recurrence = HolidayRecurrence.nthWeekday(ordinal: -1, weekday: 2, month: 5)
        XCTAssertEqual(recurrence.occurrence(inYear: 2026, calendar: calendar), Fixture.date(2026, 5, 25))
    }

    func testAFifthWeekdayThatDoesNotExistSimplyDoesNotOccur() {
        let recurrence = HolidayRecurrence.nthWeekday(ordinal: 5, weekday: 2, month: 5)
        XCTAssertNil(recurrence.occurrence(inYear: 2026, calendar: calendar), "May 2026 has only four Mondays")
    }

    func testTheTwentyNinthOfFebruaryIsSkippedRatherThanMoved() {
        let recurrence = HolidayRecurrence.annual(month: 2, day: 29)
        XCTAssertEqual(recurrence.occurrence(inYear: 2024, calendar: calendar), Fixture.date(2024, 2, 29))
        XCTAssertNil(recurrence.occurrence(inYear: 2026, calendar: calendar))
    }

    func testYearBoundsLimitARecurringRule() {
        var recurrence = HolidayRecurrence.annual(month: 5, day: 1)
        recurrence.startYear = 2025
        recurrence.endYear = 2027

        XCTAssertNil(recurrence.occurrence(inYear: 2024, calendar: calendar))
        XCTAssertNotNil(recurrence.occurrence(inYear: 2025, calendar: calendar))
        XCTAssertNotNil(recurrence.occurrence(inYear: 2027, calendar: calendar))
        XCTAssertNil(recurrence.occurrence(inYear: 2028, calendar: calendar))
    }

    // MARK: - Resolver

    func testTheResolverFindsHolidaysAcrossAWholeYear()  {
        let rules = [
            HolidayRule(name: "New Year", recurrence: .annual(month: 1, day: 1)),
            HolidayRule(name: "Labour Day", recurrence: .annual(month: 5, day: 1)),
            HolidayRule(name: "Christmas", recurrence: .annual(month: 12, day: 25))
        ]
        let resolver = HolidayResolver(
            rules: rules,
            calendar: calendar,
            covering: CalendarDateRange.year(2026, in: calendar)
        )

        XCTAssertTrue(resolver.isHoliday(Fixture.date(2026, 1, 1)))
        XCTAssertTrue(resolver.isHoliday(Fixture.date(2026, 12, 25)))
        XCTAssertFalse(resolver.isHoliday(Fixture.date(2026, 6, 15)))
        XCTAssertEqual(resolver.primaryHoliday(on: Fixture.date(2026, 5, 1))?.name, "Labour Day")
    }

    func testADisabledRuleIsNotApplied() {
        let rule = HolidayRule(
            name: "Off",
            recurrence: .annual(month: 5, day: 1),
            isEnabled: false
        )
        let resolver = HolidayResolver(
            rules: [rule],
            calendar: calendar,
            covering: CalendarDateRange.year(2026, in: calendar)
        )
        XCTAssertFalse(resolver.isHoliday(Fixture.date(2026, 5, 1)))
    }

    func testPaidAbsenceWinsWhenTwoHolidaysCoincide() {
        let working = HolidayRule(
            name: "Company day",
            recurrence: .annual(month: 5, day: 1),
            countsAsWorkingDay: true
        )
        let absence = HolidayRule(name: "Labour Day", recurrence: .annual(month: 5, day: 1))
        let resolver = HolidayResolver(
            rules: [working, absence],
            calendar: calendar,
            covering: CalendarDateRange.year(2026, in: calendar)
        )

        XCTAssertEqual(resolver.holidays(on: Fixture.date(2026, 5, 1)).count, 2)
        XCTAssertEqual(resolver.primaryHoliday(on: Fixture.date(2026, 5, 1))?.name, "Labour Day")
    }

    func testAHolidayReducesTheHoursOwedForTheMonth() {
        let holiday = HolidayRule(name: "Assumption", recurrence: .annual(month: 8, day: 4))
        let august = YearMonth(year: 2026, month: 8).range(in: calendar)

        let summary = Fixture.engine(calendar: calendar).summary(
            in: august,
            records: [:],
            holidays: [holiday],
            countingThrough: Fixture.date(2026, 12, 31)
        )

        XCTAssertEqual(summary.count(of: .holiday), 1)
        XCTAssertEqual(summary.creditedMinutes, 480)
        XCTAssertEqual(
            summary.scheduledWorkingDays,
            20,
            "the holiday is no longer one of the 21 days you are expected to work"
        )
    }
}

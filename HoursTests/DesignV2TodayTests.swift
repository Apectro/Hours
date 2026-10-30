import XCTest
@testable import Hours

/// The engine under design v2's Today tab, a day's sheet and the day
/// editor: the editor's four main types (Work, Vacation, Sick, Day off),
/// the difference to a normal day, the calendar's "8.5h" and a day's
/// "Thursday 29".
final class DesignV2TodayTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let catalog = DayTypeCatalog.standard

    private func definition(_ id: DayTypeID) -> DayTypeDefinition { catalog.definition(for: id) }

    // MARK: - Work · Vacation · Sick · Day off

    func testEachBuiltInTypeHasItsChoice() {
        func choice(_ id: DayTypeID) -> DayEditorChoice { DayEditorChoice.of(definition(id)) }

        XCTAssertEqual(choice(.work), .work)
        XCTAssertEqual(choice(.other), .work, "Other takes times, so it is a kind of work")
        XCTAssertEqual(choice(.vacation), .vacation)
        XCTAssertEqual(choice(.sick), .sick)
        XCTAssertEqual(choice(.dayOff), .dayOff)
        XCTAssertEqual(choice(.weekend), .dayOff, "the weekend is a day off")
        XCTAssertEqual(choice(.holiday), .other, "a public holiday is none of the four")
        XCTAssertEqual(choice(.personal), .other)
        XCTAssertEqual(choice(.timeOffInLieu), .other)
        XCTAssertEqual(choice(.badWeather), .other)
    }

    func testTheSegmentsAreTheFourMainTypesInOrder() {
        XCTAssertEqual(DayEditorChoice.segments, [.work, .vacation, .sick, .dayOff])
    }

    func testChoosingSickOnAWorkingDayDropsYourTimesAndKeepsTheSitesHours() {
        let site = Shift(start: Fixture.time(7), end: Fixture.time(11), siteID: UUID())
        let own = Shift(start: Fixture.time(12), end: Fixture.time(16))
        let record = DayRecord(date: Fixture.workingTuesday, shifts: [site, own])

        let sick = DayEditorChoice.sick.apply(to: record, automatic: definition(.work), catalog: catalog, prefilled: own)

        XCTAssertEqual(sick.dayTypeID, .sick)
        XCTAssertEqual(sick.shifts, [site])
    }

    func testChoosingSickOnAVacationDaySwitchesTheType() {
        let record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .vacation)

        let sick = DayEditorChoice.sick.apply(to: record, automatic: definition(.work), catalog: catalog, prefilled: Shift())

        XCTAssertEqual(sick.dayTypeID, .sick)
    }

    func testChoosingVacationKeepsAHalfDay() {
        let contracted = 480
        let record = DayRecord(
            date: Fixture.workingTuesday,
            dayTypeID: .sick,
            expectedOverrideMinutes: HalfDay.minutes(contracted: contracted)
        )

        let vacation = DayEditorChoice.vacation.apply(
            to: record, automatic: definition(.work), catalog: catalog, prefilled: Shift(), contractedMinutes: contracted
        )

        XCTAssertEqual(vacation.dayTypeID, .vacation)
        XCTAssertEqual(vacation.expectedOverrideMinutes, 240, "half a day of leave stays half a day")
    }

    func testChoosingVacationWhereTheDayAlreadyIsOneLeavesItAutomatic() {
        let record = DayRecord(date: Fixture.workingTuesday)

        let vacation = DayEditorChoice.vacation.apply(
            to: record, automatic: definition(.vacation), catalog: catalog, prefilled: Shift()
        )

        XCTAssertNil(vacation.dayTypeID)
    }

    func testChoosingWorkIsWhatWorkedDoes() {
        let usual = Shift(start: Fixture.time(8), end: Fixture.time(16, 30), breaks: [.duration(30)])
        let record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .sick)

        let work = DayEditorChoice.work.apply(to: record, automatic: definition(.work), catalog: catalog, prefilled: usual)
        let worked = DayKind.worked.apply(to: record, automatic: definition(.work), catalog: catalog, prefilled: usual)

        XCTAssertEqual(work, worked)
        XCTAssertNil(work.dayTypeID)
        XCTAssertEqual(work.shifts, [usual])
    }

    func testChoosingDayOffOnAWorkingDayMakesItADayOff() {
        let record = DayRecord(date: Fixture.workingTuesday, shifts: [Shift(start: Fixture.time(8), end: Fixture.time(12))])

        let off = DayEditorChoice.dayOff.apply(to: record, automatic: definition(.work), catalog: catalog, prefilled: Shift())

        XCTAssertEqual(off.dayTypeID, .dayOff)
        XCTAssertTrue(off.shifts.isEmpty)
    }

    func testChoosingDayOffFromSickMakesItADayOffNotSick() {
        let record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .sick)

        let off = DayEditorChoice.dayOff.apply(to: record, automatic: definition(.work), catalog: catalog, prefilled: Shift())

        XCTAssertEqual(off.dayTypeID, .dayOff)
    }

    func testChoosingDayOffOnTheWeekendLeavesItAutomatic() {
        let record = DayRecord(date: Fixture.workingTuesday)

        let off = DayEditorChoice.dayOff.apply(to: record, automatic: definition(.weekend), catalog: catalog, prefilled: Shift())

        XCTAssertNil(off.dayTypeID, "the weekend is already a day off")
    }

    func testOtherChangesNothing() {
        let record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .personal)

        let same = DayEditorChoice.other.apply(to: record, automatic: definition(.work), catalog: catalog, prefilled: Shift())

        XCTAssertEqual(same, record)
    }

    // MARK: - Against a normal day

    private func day(_ record: DayRecord?) -> DayComputation {
        let engine = PeriodEngine(settings: Fixture.settings(), calendar: calendar, firstRecorded: nil)
        return engine.day(record?.date ?? Fixture.workingTuesday, record: record, holidays: [])
    }

    func testHalfAnHourLongerIsThirtyMinutesMore() {
        // The fixture's normal day: 08:00–16:30 with a 30-minute break, 8h.
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [Shift(start: Fixture.time(8), end: Fixture.time(17), breaks: [.duration(30)])]
        )

        XCTAssertEqual(day(record).differenceFromNormalDay, 30)
    }

    func testAShortDayIsANegativeDifference() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [Shift(start: Fixture.time(8), end: Fixture.time(15), breaks: [.duration(30)])]
        )

        XCTAssertEqual(day(record).differenceFromNormalDay, -90)
    }

    func testANormalDayHasNoDifference() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [Shift(start: Fixture.time(8), end: Fixture.time(16, 30), breaks: [.duration(30)])]
        )

        XCTAssertEqual(day(record).differenceFromNormalDay, 0)
    }

    func testADayNotWrittenHasNoDifference() {
        XCTAssertNil(day(nil).differenceFromNormalDay, "nothing to compare yet")
    }

    func testADayWithNothingExpectedHasNoDifference() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            dayTypeID: .dayOff,
            shifts: [Shift(start: Fixture.time(8), end: Fixture.time(12))]
        )

        XCTAssertNil(day(record).differenceFromNormalDay, "no normal day to compare a day off with")
    }

    func testACorrectionIsNotPartOfTheDifference() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [Shift(start: Fixture.time(8), end: Fixture.time(16, 30), breaks: [.duration(30)])],
            adjustmentMinutes: 60
        )

        XCTAssertEqual(day(record).differenceFromNormalDay, 0, "a correction is not time worked")
    }

    // MARK: - The calendar's hours

    func testWholeHoursHaveNoDecimals() {
        XCTAssertEqual(DurationFormatting.compactHours(480), "8h")
        XCTAssertEqual(DurationFormatting.compactHours(600), "10h")
    }

    func testHalfHoursHaveOneDecimal() {
        XCTAssertEqual(DurationFormatting.compactHours(510), "8.5h")
        XCTAssertEqual(DurationFormatting.compactHours(510, decimalSeparator: ","), "8,5h")
    }

    func testOddMinutesRoundToATenth() {
        XCTAssertEqual(DurationFormatting.compactHours(500), "8.3h")
        XCTAssertEqual(DurationFormatting.compactHours(477), "8h", "7.95 rounds to 8.0, which is written 8h")
        XCTAssertEqual(DurationFormatting.compactHours(20), "0.3h")
    }

    func testNoTimeIsNothing() {
        XCTAssertEqual(DurationFormatting.compactHours(0), "")
        XCTAssertEqual(DurationFormatting.compactHours(-30), "")
    }

    // MARK: - A day's title

    func testADaysTitleIsItsWeekdayAndNumber() {
        let formatting = CalendarFormatting(locale: Locale(identifier: "en_GB"), calendar: calendar)
        let title = formatting.weekdayAndDay(Fixture.date(2026, 10, 29))

        XCTAssertTrue(title.contains("Thursday"), title)
        XCTAssertTrue(title.contains("29"), title)
        XCTAssertFalse(title.contains("Oct"), "the month is the screen's title: \(title)")
        XCTAssertFalse(title.contains("2026"), title)
    }
}

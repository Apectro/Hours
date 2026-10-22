import XCTest
@testable import Hours

/// Time off in lieu — Zeitausgleich: a working day taken off against the
/// overtime already built up. The day is still expected, nothing is worked
/// and nothing is credited, so the balance goes down by exactly the day's
/// contracted hours.
final class TimeOffInLieuTests: XCTestCase {
    private let calendar = Fixture.calendar()

    private func compute(_ record: DayRecord?, on date: CalendarDate, settings: AppSettings = Fixture.settings()) -> DayComputation {
        Fixture.calculator(settings: settings, calendar: calendar).compute(record: record, on: date)
    }

    func testItShipsAsABuiltInWorkingDayWithoutTimes() {
        let definition = DayTypeCatalog.standard.definition(for: .timeOffInLieu)
        XCTAssertTrue(definition.isBuiltIn)
        XCTAssertTrue(DayTypeCatalog.isBuiltIn(.timeOffInLieu))
        XCTAssertEqual(definition.expectation, .scheduled)
        XCTAssertFalse(definition.showsTimesByDefault)
        XCTAssertEqual(definition.name, "Time off in lieu")
        XCTAssertEqual(DayTypeID.timeOffInLieu.rawValue, "timeOffInLieu")
    }

    func testItTakesTheDaysExpectedHoursOffTheBalance() {
        let day = compute(Fixture.record(on: Fixture.workingTuesday, type: .timeOffInLieu), on: Fixture.workingTuesday)
        XCTAssertEqual(day.workedMinutes, 0)
        XCTAssertEqual(day.creditedMinutes, 0)
        XCTAssertEqual(day.expectedMinutes, 480)
        XCTAssertEqual(day.balanceMinutes, -480)
    }

    func testItCostsExactlyWhatAnEmptyWorkingDayCosts() {
        // A short Friday: the schedule in force decides, nothing else.
        var schedule = WorkSchedule()
        schedule.setContractedMinutes(390, forWeekday: 6)
        let settings = Fixture.settings(schedule: schedule)
        let friday = Fixture.date(2026, 8, 7)
        let toil = compute(Fixture.record(on: friday, type: .timeOffInLieu), on: friday, settings: settings)
        let empty = compute(nil, on: friday, settings: settings)
        XCTAssertEqual(toil.balanceMinutes, -390)
        XCTAssertEqual(toil.balanceMinutes, empty.balanceMinutes)
        XCTAssertEqual(toil.expectedMinutes, empty.expectedMinutes)
    }

    func testOnADayNothingIsExpectedItCostsNothing() {
        let day = compute(Fixture.record(on: Fixture.saturday, type: .timeOffInLieu), on: Fixture.saturday)
        XCTAssertEqual(day.balanceMinutes, 0)
    }

    func testItIsNotAGapAndNotAProblem() {
        let day = compute(Fixture.record(on: Fixture.workingTuesday, type: .timeOffInLieu), on: Fixture.workingTuesday)
        XCTAssertFalse(day.isUnrecordedWorkingDay(asOf: Fixture.date(2026, 9, 1)))
        XCTAssertFalse(day.hasProblem, "no times were expected, so none are missing")
        XCTAssertTrue(day.warnings.isEmpty)
    }

    func testTheMonthReadsTheSameAsTheDays() {
        let engine = Fixture.engine()
        let august = YearMonth(year: 2026, month: 8).range(in: calendar)
        var records: [Int: DayRecord] = [:]
        for date in august.days(in: calendar) where date.weekday(in: calendar) != 1 && date.weekday(in: calendar) != 7 {
            records[date.key] = Fixture.record(on: date, start: Fixture.time(8), end: Fixture.time(16))
        }
        records[Fixture.workingTuesday.key] = Fixture.record(on: Fixture.workingTuesday, type: .timeOffInLieu)
        let summary = engine.summary(in: august, records: records, holidays: [])
        XCTAssertEqual(summary.balanceMinutes, -480)
        XCTAssertEqual(summary.count(of: .timeOffInLieu), 1)
        XCTAssertEqual(summary.paidAbsenceDays, 0, "it is not paid absence: the hours come out of the balance")
    }

    func testItIsNamedInEveryLanguage() {
        let definition = DayTypeCatalog.standard.definition(for: .timeOffInLieu)
        XCTAssertEqual(definition.displayName(in: .german), "Zeitausgleich")
        XCTAssertEqual(definition.displayName(in: .english), "Time off in lieu")
        for language in ExportLanguage.allCases where language != .device && language != .english {
            XCTAssertNotEqual(definition.displayName(in: language), "Time off in lieu", "\(language)")
        }
    }

    func testTheWidgetDoesNotDrawItAsAShortDayOrSayWhenItEnds() {
        let engine = Fixture.engine()
        let august = YearMonth(year: 2026, month: 8).range(in: calendar)
        let days = engine.days(in: august, records: [
            Fixture.workingTuesday.key: Fixture.record(on: Fixture.workingTuesday, type: .timeOffInLieu)
        ], holidays: [])
        let marks = WidgetSnapshotBuilder.monthMarks(days, today: Fixture.date(2026, 8, 6))
        XCTAssertFalse(marks.contains { $0.date == Fixture.workingTuesday })
        let tuesday = days.first { $0.date == Fixture.workingTuesday }
        XCTAssertNil(WidgetSnapshotBuilder.defaultEnd(today: tuesday, running: nil, settings: Fixture.settings()))
    }

    /// An existing install gets the new type without anything being written:
    /// settings from before it existed hold only their own custom types.
    func testSettingsFromBeforeItExistedOfferIt() throws {
        let custom = DayTypeDefinition(
            id: DayTypeID("8B0F1C2E-0000-0000-0000-000000000001"), name: "Site visit", symbolName: "car",
            tint: .blue, expectation: .scheduled, showsTimesByDefault: true
        )
        let old = Fixture.settings(customDayTypes: [custom])
        let data = try JSONEncoder().encode(old)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        let ids = decoded.dayTypeCatalog.all.map(\.id)
        XCTAssertTrue(ids.contains(.timeOffInLieu))
        XCTAssertTrue(ids.contains(custom.id))
    }
}
